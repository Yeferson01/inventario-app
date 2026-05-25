import { supabase } from './supabaseClient.js'

async function test() {

  const { data, error } =
    await supabase.auth.getSession()

  console.log(data)
  console.log(error)

}

test()