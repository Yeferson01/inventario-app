import { supabase } from './supabaseClient.js'
import { v7 as uuidv7 } from 'uuid'

async function run() {

  try {

    // =========================================
    // LOGIN
    // =========================================

    const email = 'tienda1779471207348@gmail.com'
    const password = 'test123456'

    const {
      data: loginData,
      error: loginError
    } = await supabase.auth.signInWithPassword({
      email,
      password
    })

    console.log('\n===== LOGIN =====')

    if (loginError) {
      console.log(loginError)
      return
    }

    console.log(loginData.user.email)

    const userId = loginData.user.id

    // =========================================
    // PROFILE
    // =========================================

    const {
      data: profile,
      error: profileError
    } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', userId)
      .single()

    if (profileError) {
      console.log(profileError)
      return
    }

    const businessId = profile.business_id

    // =========================================
    // PRODUCTO
    // =========================================

    const {
      data: product,
      error: productError
    } = await supabase
      .from('products')
      .select('*')
      .eq('barcode', '7702535010101')
      .eq('business_id', businessId)
      .single()

    console.log('\n===== PRODUCT =====')

    if (productError) {
      console.log(productError)
      return
    }

    console.log(product)

    console.log('\n===== CURRENT STOCK =====')
    console.log(product.stock_quantity)

    // =========================================
    // CREAR VENTA
    // =========================================

    const saleId = uuidv7()

    const {
      data: saleData,
      error: saleError
    } = await supabase
      .from('sales')
      .insert({
        id: saleId,
        business_id: businessId,
        total: 7500,
        payment_method: 'cash'
      })
      .select()
      .single()

    console.log('\n===== SALE =====')

    if (saleError) {
      console.log(saleError)
      return
    }

    console.log(saleData)

    // =========================================
    // SALE ITEMS
    // =========================================

    const {
      data: saleItemsData,
      error: saleItemsError
    } = await supabase
      .from('sale_items')
      .insert({
        id: uuidv7(),
        sale_id: saleId,
        product_id: product.id,
        quantity: 3,
        unit_price: 2500,
        subtotal: 7500
      })
      .select()

    console.log('\n===== SALE ITEMS =====')

    if (saleItemsError) {
      console.log(saleItemsError)
      return
    }

    console.log(saleItemsData)

    // =========================================
    // STOCK FINAL
    // =========================================

    const {
      data: finalProduct,
      error: finalProductError
    } = await supabase
      .from('products')
      .select('id, name, stock_quantity')
      .eq('id', product.id)
      .single()

    console.log('\n===== FINAL STOCK =====')

    if (finalProductError) {
      console.log(finalProductError)
      return
    }

    console.log(finalProduct)

    // =========================================
    // INVENTORY MOVEMENTS
    // =========================================

    const {
      data: movements,
      error: movementsError
    } = await supabase
      .from('inventory_movements')
      .select('*')
      .eq('reference_id', saleId)

    console.log('\n===== INVENTORY MOVEMENTS =====')

    if (movementsError) {
      console.log(movementsError)
      return
    }

    console.log(movements)

  } catch (error) {

    console.log('\n===== ERROR GENERAL =====')
    console.log(error)

  }

}

run()