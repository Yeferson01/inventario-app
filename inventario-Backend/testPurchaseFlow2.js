import { supabase } from './supabaseClient.js'
import { v7 as uuidv7 } from 'uuid'

async function run() {
  try {
    // =========================================
    // LOGIN
    // =========================================
    const email = 'tienda1779471207348@gmail.com'
    const password = 'test123456'

    const { data: loginData, error: loginError } = await supabase.auth.signInWithPassword({
      email,
      password
    })

    console.log('\n===== LOGIN =====')
    if (loginError) return console.log('Error Login:', loginError.message)
    console.log('Usuario:', loginData.user.email)

    const userId = loginData.user.id

    // =========================================
    // PROFILE
    // =========================================
    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', userId)
      .single()

    if (profileError) return console.log('Error Perfil:', profileError.message)
    const businessId = profile.business_id

    // =========================================
    // PRODUCTO (BUSCAR O CREAR)
    // =========================================
    const targetBarcode = '7702535010101'
    
    let { data: product, error: productError } = await supabase
      .from('products')
      .select('*')
      .eq('barcode', targetBarcode)
      .eq('business_id', businessId)
      .maybeSingle() // Evita el error PGRST116 si no existe

    if (productError) return console.log('Error Producto:', productError.message)

    console.log('\n===== PRODUCT =====')
    if (!product) {
      console.log('El producto no existe. Creándolo automáticamente...')
      
      const { data: newProduct, error: createError } = await supabase
        .from('products')
        .insert({
          id: uuidv7(),
          business_id: businessId,
          name: 'Producto Autocreado',
          barcode: targetBarcode,
          stock_quantity: 0, // Inicia en cero, la compra sumará stock
          sale_price: 3000
        })
        .select()
        .single()

      if (createError) return console.log('Error al crear producto:', createError.message)
      product = newProduct
    }

    console.log('Producto Listo:', product.name, `(ID: ${product.id})`)
    console.log('Stock Actual:', product.stock_quantity)

    // =========================================
    // CREAR COMPRA
    // =========================================
    const purchaseId = uuidv7()

    const { data: purchaseData, error: purchaseError } = await supabase
      .from('purchases')
      .insert({
        id: purchaseId,
        business_id: businessId,
        total: 40000
      })
      .select()
      .single()

    console.log('\n===== PURCHASE =====')
    if (purchaseError) return console.log('Error Compra:', purchaseError.message)
    console.log('Compra Registrada:', purchaseData.id)

    // =========================================
    // PURCHASE ITEMS
    // =========================================
    const { data: purchaseItemsData, error: purchaseItemsError } = await supabase
      .from('purchase_items')
      .insert({
        id: uuidv7(),
        purchase_id: purchaseId,
        product_id: product.id,
        quantity: 20,
        unit_cost: 2000,
        subtotal: 40000
      })
      .select()

    console.log('\n===== PURCHASE ITEMS =====')
    if (purchaseItemsError) return console.log('Error Items Compra:', purchaseItemsError.message)
    console.log('Items Insertados:', purchaseItemsData.length)

    // =========================================
    // STOCK FINAL
    // =========================================
    const { data: finalProduct, error: finalProductError } = await supabase
      .from('products')
      .select('id, name, stock_quantity')
      .eq('id', product.id)
      .single()

    console.log('\n===== FINAL STOCK =====')
    if (finalProductError) return console.log('Error Stock Final:', finalProductError.message)
    console.log(`Stock final de [${finalProduct.name}]:`, finalProduct.stock_quantity)

    // =========================================
    // INVENTORY MOVEMENTS
    // =========================================
    const { data: movements, error: movementsError } = await supabase
      .from('inventory_movements')
      .select('*')
      .eq('reference_id', purchaseId)

    console.log('\n===== INVENTORY MOVEMENTS =====')
    if (movementsError) return console.log('Error Movimientos:', movementsError.message)
    console.log('Movimientos generados por trigger/función:', movements)

  } catch (error) {
    console.log('\n===== ERROR GENERAL =====')
    console.log(error)
  }
}

run()
