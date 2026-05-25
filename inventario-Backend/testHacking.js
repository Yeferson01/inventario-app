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

    const myBusinessId = profile.business_id
    console.log('Mi ID de Negocio real:', myBusinessId)

    // =========================================
    // HACK TEST (INSERCIÓN)
    // =========================================
    console.log('\n===== HACK TEST =====')
    
    // Generamos un UUID falso simulando el ID de otra empresa
    const fakeBusinessId = '00000000-0000-0000-0000-000000000000' 

    const { data, error } = await supabase
      .from('products')
      .insert({
        id: uuidv7(),
        business_id: fakeBusinessId, // Aquí intentamos vulnerar el sistema
        name: 'Hack Test',
        barcode: '999999',
        stock_quantity: 1,
        sale_price: 1000
      })
      .select() // Añadido para que devuelva el registro si tiene éxito

    if (error) {
      console.log('Resultado: Intento bloqueado con éxito o fallido.')
      console.log('Detalle del error:', error.message)
    } else {
      console.log('Resultado: ¡Peligro! El sistema permitió la inserción.')
      console.log('Datos insertados:', data)
    }

  } catch (error) {
    console.log('\n===== ERROR GENERAL =====')
    console.log(error)
  }
}

run()
