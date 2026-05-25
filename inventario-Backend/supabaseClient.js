import { createClient } from '@supabase/supabase-js'

const supabaseUrl = 'https://mtisfzthiyusmqfuhydp.supabase.co'
const supabaseKey = 'sb_publishable_FGyvP7AFtm6qntlhOCysxQ_gPRkYaz7'

export const supabase = createClient(
  supabaseUrl,
  supabaseKey
)