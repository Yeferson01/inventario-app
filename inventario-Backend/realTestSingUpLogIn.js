import { supabase } from './supabaseClient.js'

async function run() {

  // ====================================
  // DATOS DINÁMICOS
  // ====================================

  const email = `tienda${Date.now()}@gmail.com`
  const password = 'test123456'

  // ====================================
  // REGISTRO
  // ====================================

  const {
    data: signupData,
    error: signupError
  } = await supabase.auth.signUp({
    email,
    password,
    options: {
      data: {
        full_name: 'Tienda vendeMenos'
      }
    }
  })

  console.log('\n===== SIGNUP =====')
  console.log(signupData)
  console.log(signupError)

  // ====================================
  // LOGIN
  // ====================================

  const {
    data: loginData,
    error: loginError
  } = await supabase.auth.signInWithPassword({
    email,
    password
  })

  console.log('\n===== LOGIN =====')
  console.log(loginData)
  console.log(loginError)

}

run()