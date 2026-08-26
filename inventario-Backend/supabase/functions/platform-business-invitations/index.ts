import { createClient } from "npm:@supabase/supabase-js@2";

type JsonObject = Record<string, unknown>;

type InvitationIssueResponse = {
  invitation_id: string;
  email: string;
  status: "pending" | "accepted" | "revoked";
  delivery_status: "pending" | "sent" | "failed" | "unknown";
  business_id: string;
  branch_id: string;
  created: boolean;
};

const jsonHeaders = {
  "content-type": "application/json; charset=utf-8",
};

function jsonResponse(status: number, body: JsonObject): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

function requiredString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`${field} is required`);
  }

  return value.trim();
}

function optionalString(value: unknown): string | null {
  if (value == null) return null;
  if (typeof value !== "string") throw new Error("Expected a string value");
  const normalized = value.trim();
  return normalized.length === 0 ? null : normalized;
}

function safeDeliveryErrorCode(error: unknown): string {
  const candidate = error as { status?: number; code?: string; message?: string };
  const message = (candidate?.message ?? "").toLowerCase();

  if (
    candidate?.status === 422 ||
    message.includes("already registered") ||
    message.includes("already been registered") ||
    message.includes("already exists")
  ) {
    return "existing_auth_user_notification_required";
  }

  if (candidate?.code) {
    return `auth_admin_${candidate.code}`.slice(0, 200);
  }

  if (candidate?.status) {
    return `auth_admin_http_${candidate.status}`;
  }

  return "auth_admin_delivery_failed";
}

async function secureTokenEquals(left: string, right: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const [leftDigest, rightDigest] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(left)),
    crypto.subtle.digest("SHA-256", encoder.encode(right)),
  ]);
  const leftBytes = new Uint8Array(leftDigest);
  const rightBytes = new Uint8Array(rightDigest);
  let difference = 0;

  for (let index = 0; index < leftBytes.length; index += 1) {
    difference |= leftBytes[index] ^ rightBytes[index];
  }

  return difference === 0;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return jsonResponse(405, { error: "method_not_allowed" });
  }

  const authorization = request.headers.get("authorization");
  if (!authorization) {
    return jsonResponse(401, { error: "authorization_required" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return jsonResponse(500, { error: "server_configuration_missing" });
  }

  let payload: JsonObject;
  try {
    const parsed = await request.json();
    if (parsed == null || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("JSON object required");
    }
    payload = parsed as JsonObject;
  } catch (error) {
    return jsonResponse(400, {
      error: "invalid_request",
      message: error instanceof Error ? error.message : "Invalid JSON body",
    });
  }

  let email: string;
  let businessName: string;
  let idempotencyKey: string;
  let branchName: string | null;
  let expiresAt: string | null;

  try {
    email = requiredString(payload.email, "email");
    businessName = requiredString(payload.business_name, "business_name");
    idempotencyKey = requiredString(
      payload.idempotency_key,
      "idempotency_key",
    );
    branchName = optionalString(payload.branch_name);
    expiresAt = optionalString(payload.expires_at);
  } catch (error) {
    return jsonResponse(400, {
      error: "invalid_request",
      message: error instanceof Error ? error.message : "Invalid request",
    });
  }

  const metadata = payload.metadata ?? {};
  if (typeof metadata !== "object" || metadata == null || Array.isArray(metadata)) {
    return jsonResponse(400, {
      error: "invalid_request",
      message: "metadata must be a JSON object",
    });
  }

  // The caller JWT, not this function's server credential, invokes the
  // issuance RPC. Its service_role-only ACL remains a second authority gate.
  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const bearerMatch = authorization.match(/^Bearer\s+(.+)$/i);
  if (!bearerMatch) {
    return jsonResponse(401, { error: "invalid_authorization" });
  }

  const bearerToken = bearerMatch[1];
  const isTrustedServiceRole = await secureTokenEquals(
    bearerToken,
    serviceRoleKey,
  );

  if (!isTrustedServiceRole) {
    // getClaims verifies non-administrative tokens through Supabase Auth/JWKS
    // so invalid credentials remain 401. Every valid non-service credential is
    // 403: business roles and permissions never grant platform authority.
    const { data: claimsData, error: claimsError } =
      await callerClient.auth.getClaims(bearerToken);

    if (claimsError || claimsData?.claims == null) {
      return jsonResponse(401, { error: "invalid_authorization" });
    }

    return jsonResponse(403, { error: "platform_authority_required" });
  }

  const { data: issuedData, error: issuanceError } = await callerClient.rpc(
    "admin_create_platform_business_invitation",
    {
      p_email: email,
      p_business_name: businessName,
      p_idempotency_key: idempotencyKey,
      p_branch_name: branchName ?? "Principal",
      p_expires_at: expiresAt,
      p_metadata: metadata,
    },
  );

  if (issuanceError) {
    const status = issuanceError.code === "42501" ? 403 : 409;
    return jsonResponse(status, {
      error: "invitation_issuance_rejected",
      code: issuanceError.code,
      message: issuanceError.message,
    });
  }

  if (
    issuedData == null ||
    typeof issuedData !== "object" ||
    typeof (issuedData as JsonObject).invitation_id !== "string"
  ) {
    return jsonResponse(500, { error: "invalid_issuance_response" });
  }

  const invitation = issuedData as InvitationIssueResponse;

  // A logical retry never sends again after a prior claim. pending -> unknown
  // is an atomic delivery lease; a crash leaves an explicit unknown state for
  // controlled administrative follow-up instead of risking duplicate email.
  if (
    invitation.status !== "pending" ||
    invitation.delivery_status !== "pending"
  ) {
    return jsonResponse(200, {
      invitation,
      delivery_attempted: false,
      delivery_status: invitation.delivery_status,
    });
  }

  const { data: claimData, error: claimError } = await callerClient.rpc(
    "admin_claim_platform_business_invitation_delivery",
    { p_invitation_id: invitation.invitation_id },
  );

  if (claimError) {
    return jsonResponse(500, {
      error: "delivery_claim_failed",
      code: claimError.code,
      invitation,
    });
  }

  const claim = claimData as {
    claimed: boolean;
    delivery_status: string;
  };

  if (!claim.claimed) {
    return jsonResponse(200, {
      invitation,
      delivery_attempted: false,
      delivery_status: claim.delivery_status,
    });
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const redirectTo = optionalString(
    Deno.env.get("PLATFORM_INVITATION_REDIRECT_URL"),
  );

  const { error: deliveryError } = await adminClient.auth.admin.inviteUserByEmail(
    invitation.email,
    {
      data: {
        platform_invitation_id: invitation.invitation_id,
      },
      ...(redirectTo ? { redirectTo } : {}),
    },
  );

  const deliveryErrorCode = deliveryError
    ? safeDeliveryErrorCode(deliveryError)
    : null;
  const deliveryStatus = deliveryError
    ? deliveryErrorCode === "existing_auth_user_notification_required"
      ? "unknown"
      : "failed"
    : "sent";

  const { data: deliveryData, error: deliveryUpdateError } =
    await callerClient.rpc(
      "admin_update_platform_business_invitation_delivery",
      {
        p_invitation_id: invitation.invitation_id,
        p_delivery_status: deliveryStatus,
        p_error_code: deliveryErrorCode,
      },
    );

  if (deliveryUpdateError) {
    return jsonResponse(500, {
      error: "delivery_state_update_failed",
      code: deliveryUpdateError.code,
      invitation,
      delivery_attempted: true,
      delivery_result: "unknown",
    });
  }

  return jsonResponse(deliveryError ? 202 : 200, {
    invitation,
    delivery_attempted: true,
    delivery: deliveryData,
    existing_user_notification_required:
      deliveryErrorCode === "existing_auth_user_notification_required",
  });
});
