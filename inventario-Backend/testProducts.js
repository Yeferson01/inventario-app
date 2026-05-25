import { supabase } from './supabaseClient.js'
import { v7 as uuidv7 } from 'uuid'

async function run() {
  try {
    // =========================================
    // LOGIN
    // =========================================
    const email = 'tienda1779391810991@gmail.com'
    const password = 'test123456'

    const { data: loginData, error: loginError } = await supabase.auth.signInWithPassword({
      email,
      password
    })

    console.log('\n===== LOGIN =====')

    if (loginError) {
      console.log('Error en Login:', loginError.message)
      return
    }

    console.log('Usuario autenticado:', loginData.user.email)
    const userId = loginData.user.id

    // =========================================
    // PROFILE
    // =========================================
    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', userId)
      .single()

    if (profileError) {
      console.log('Error en Perfil:', profileError.message)
      return
    }

    const businessId = profile.business_id
    console.log('ID de Negocio:', businessId)

    // =========================================
    // PRODUCTS TEST
    // =========================================
    const { data: productsTest, error: productsTestError } = await supabase
      .from('products')
      .select('*')

    console.log('\n===== PRODUCTS TEST =====')
    if (productsTestError) {
      console.log('Error en Productos:', productsTestError.message)
    } else {
      console.log('Productos encontrados:', productsTest)
    }

  } catch (error) {
    console.log('\n===== ERROR GENERAL =====')
    console.log(error)
  }
}

run()
