import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Offline Mode'),
            subtitle: const Text('Force map to use downloaded tile files'),
            value: true,
            onChanged: (val) {},
          ),
          SwitchListTile(
            title: const Text('Voice Navigation'),
            subtitle: const Text('Turn-by-turn spoken instructions'),
            value: true,
            onChanged: (val) {},
          ),
          ListTile(
            title: const Text('Map Downloads'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.pushNamed(context, '/downloads');
            },
          ),
          ListTile(
            title: const Text('Account'),
            subtitle: const Text('Login / Sync Data'),
            trailing: const Icon(Icons.account_circle),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}
