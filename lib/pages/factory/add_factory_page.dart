import 'package:flutter/material.dart';

class AddFactoryPage extends StatefulWidget {
  @override
  _AddFactoryPageState createState() => _AddFactoryPageState();
}

class _AddFactoryPageState extends State<AddFactoryPage> {
  String role = "source";

  final tempController = TextEditingController();
  final outputController = TextEditingController();
  final hoursController = TextEditingController();
  final costController = TextEditingController();

  Future<void> submit() async {
    // 🚀 TEMP (no backend)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Form Submitted (Demo Mode) ✅")),
    );

    print({
      "role": role,
      "temperature": tempController.text,
      "output": outputController.text,
      "hours": hoursController.text,
      "cost": costController.text,
    });
  }

  Widget buildInput(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Add Factory"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [

            // 🔥 TITLE
            Text(
              "Enter Factory Details",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            SizedBox(height: 20),

            // 🧩 ROLE CARD
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: DropdownButtonFormField(
                  value: role,
                  items: [
                    DropdownMenuItem(
                        value: "source", child: Text("Heat Source 🔥")),
                    DropdownMenuItem(
                        value: "sink", child: Text("Heat Sink ❄️")),
                  ],
                  onChanged: (val) {
                    setState(() => role = val!);
                  },
                  decoration: InputDecoration(
                    labelText: "Select Role",
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),

            SizedBox(height: 20),

            // 🌡 INPUTS
            buildInput(
              role == "source"
                  ? "Outlet Temperature (°C)"
                  : "Required Temperature (°C)",
              tempController,
            ),

            buildInput(
              role == "source"
                  ? "Heat Output (kW)"
                  : "Required Volume (kW)",
              outputController,
            ),

            buildInput(
              "Operating Hours / Day",
              hoursController,
            ),

            buildInput(
              role == "source"
                  ? "Disposal Cost (₹/year)"
                  : "Energy Spend (₹/year)",
              costController,
            ),

            SizedBox(height: 25),

            // 🚀 SUBMIT BUTTON
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: submit,
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  "Submit",
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),

            SizedBox(height: 10),

            // 🧠 INFO TEXT
            Text(
              "Demo mode: Data is not saved yet",
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}