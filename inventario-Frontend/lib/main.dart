import 'package:flutter/material.dart';

void main() {
  // Captura las variables del Flavor inyectadas desde la consola
  const appName = String.fromEnvironment('APP_NAME', defaultValue: 'Inventario Base');
  const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');

  runApp(
    MaterialApp(
      title: appName,
      home: Scaffold(
        appBar: AppBar(title: const Text('Inventario - Inicializado')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Ambiente actual: $appName', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text('Conectado a API en: $apiUrl'),
            ],
          ),
        ),
      ),
    ),
  );
}
