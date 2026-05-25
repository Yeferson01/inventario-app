import { supabase } from './supabaseClient.js'

async function run() {

  // ====================================
  // DATOS DINÁMICOS
  // ====================================

  const email = `tienda1779471207348@gmail.com` //User 2 tienda vendemenos --- User 1 tienda1779391810991@gmail.com
  const password = 'test123456'


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

  // ====================================
  // USER ID
  // ====================================

  const userId = loginData.user.id

  console.log('\n===== USER ID =====')
  console.log(userId)

  // ====================================
  // CREAR BUSINESS
  // ====================================

  const {
    data: businessData,
    error: businessError
  } = await supabase
    .from('businesses')
    .insert({
      name: 'Tienda Test Real',
      owner_name: 'Tendero Real'
    })
    .select()
    .single()

  console.log('\n===== BUSINESS =====')
  console.log(businessData)
  console.log(businessError)

  // ====================================
  // ASOCIAR PROFILE
  // ====================================

  const {
    data: profileData,
    error: profileError
  } = await supabase
    .from('profiles')
    .update({
      business_id: businessData.id
    })
    .eq('id', userId)
    .select()

  console.log('\n===== PROFILE UPDATED =====')
  console.log(profileData)
  console.log(profileError)

}

run()