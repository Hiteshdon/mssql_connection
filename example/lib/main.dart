import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:mssql_connection/mssql_connection.dart';

void main() async {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
        debugShowCheckedModeBanner: false, home: HomPage());
  }
}

const textStyle = TextStyle(fontSize: 18);

class HomPage extends StatefulWidget {
  const HomPage({super.key});

  @override
  State<HomPage> createState() => _HomPageState();
}

class _HomPageState extends State<HomPage> {
  String ip = '',
      port = '',
      username = '',
      password = '',
      databaseName = '',
      readQuery = '',
      writeQuery = '';
  final _sqlConnection = MssqlConnection.getInstance();
  final pageController = PageController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SQL Connection Example'),
      ),
      body: PageView(
        controller: pageController,
        children: [
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(children: [
                Row(children: [
                  Flexible(
                      child: customTextField("IP address",
                          onchanged: (p0) => ip = p0,
                          keyboardType: TextInputType.number)),
                  const SizedBox(width: 10),
                  Flexible(
                      child: customTextField("Port",
                          onchanged: (p0) => port = p0,
                          keyboardType: TextInputType.number))
                ]),
                customTextField("Database Name",
                    onchanged: (p0) => databaseName = p0),
                customTextField("Username", onchanged: (p0) => username = p0),
                customTextField("Password", onchanged: (p0) => password = p0),
                const SizedBox(height: 15.0),
                FloatingActionButton.extended(
                    onPressed: connect, label: const Text("Connect"))
              ]),
            ),
          ),
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Read Data", style: textStyle),
                              IconButton(
                                  onPressed: () => execute("Read", context),
                                  icon: const Icon(Icons.play_arrow_rounded))
                            ],
                          ),
                          customTextField('query',
                              onchanged: (p0) => readQuery = p0,
                              autovalidateMode: false,
                              enableLabel: false)
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Write Data", style: textStyle),
                              IconButton(
                                  onPressed: () => execute("write", context),
                                  icon: const Icon(Icons.play_arrow_rounded))
                            ],
                          ),
                          customTextField('query',
                              onchanged: (p0) => writeQuery = p0,
                              autovalidateMode: false,
                              enableLabel: false)
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextFormField customTextField(String title,
          {void Function(String)? onchanged,
          TextInputType? keyboardType,
          bool autovalidateMode = true,
          bool enableLabel = true}) =>
      TextFormField(
        autocorrect: true,
        autovalidateMode:
            autovalidateMode ? AutovalidateMode.onUserInteraction : null,
        inputFormatters: [
          if (title == "IP address")
            FilteringTextInputFormatter.allow(RegExp(r'[\d\.]')),
          if (title == "Port") ...[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4)
          ]
        ],
        keyboardType: keyboardType,
        onChanged: onchanged,
        decoration: InputDecoration(
            border: title == "Port" || title == "IP address"
                ? const OutlineInputBorder()
                : null,
            hintText: "Enter $title ${title == "Port" ? "number" : ""}",
            labelText: enableLabel ? title : null),
        validator: (value) {
          if (value!.isEmpty) {
            return "Please Enter $title";
          }
          return null;
        },
      );

  connect() async {
    if (ip.isEmpty ||
        port.isEmpty ||
        databaseName.isEmpty ||
        username.isEmpty ||
        password.isEmpty) {
      toastMessage("Please enter all fields", color: Colors.redAccent);

      return;
    }
    _sqlConnection
        .connect(
            ip: ip,
            port: port,
            databaseName: databaseName,
            username: username,
            password: password)
        .then((value) {
      if (value) {
        toastMessage("Connection Established", color: Colors.green);
        pageController.nextPage(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut);
      } else {
        toastMessage("Connection Failed", color: Colors.redAccent);
      }
    });
  }

  Future<bool?> toastMessage(String message,
      {Color color = Colors.blueAccent}) {
    return Fluttertoast.showToast(
        msg: message,
        toastLength: Toast.LENGTH_SHORT,
        timeInSecForIosWeb: 1,
        backgroundColor: color,
        textColor: Colors.white,
        fontSize: 16.0);
  }

  execute(String s, BuildContext context) async {
    try {
      if (s == "Read") {
        if (readQuery.isEmpty) {
          toastMessage("Empty query", color: Colors.redAccent);
          return;
        }
        print(readQuery);
        showProgress(context);
        var startTime = DateTime.now();
        var result = await _sqlConnection.getData(readQuery);
        var difference = DateTime.now().difference(startTime);
        if (!mounted) return;
        hideProgress(context);
        print(
            "Duration: $difference and RecordCount:${jsonDecode(result).length}");
        toastMessage(
            "Please check the console for data.\n Duration: $difference");
        print(result.toString());
      } else {
        if (writeQuery.isEmpty) {
          toastMessage("Empty query", color: Colors.redAccent);
          return;
        }
        showProgress(context);
        var startTime = DateTime.now();
        var result = await _sqlConnection.writeData(writeQuery);
        var difference = DateTime.now().difference(startTime);
        if (!mounted) return;
        hideProgress(context);
        print("Duration: ${DateTime.now().difference(startTime)} ");
        print(result.toString());
        toastMessage(
            "Please check the console for data.\n Duration: $difference");
      }
    } on PlatformException catch (e) {
      hideProgress(context);
      toastMessage(e.message ?? "", color: Colors.redAccent);
    }
  }

  showProgress(BuildContext context,
          [String alertMessage = "Fetching Data..."]) async =>
      await showDialog(
          context: context,
          builder: (context) => AlertDialog(
                content: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox.square(
                        dimension: 35, child: CircularProgressIndicator()),
                    const SizedBox(width: 12),
                    Text(
                      alertMessage,
                      style: const TextStyle(fontSize: 20),
                    )
                  ],
                ),
              ));

  hideProgress(BuildContext context) {
    Navigator.pop(context);
  }
}
