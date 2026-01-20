import 'package:flutter/material.dart';
import 'package:italian_driving_app/Services/auth_service.dart';
import 'package:italian_driving_app/database/database_helper.dart';

class MustWrongScreen extends StatefulWidget {
  const MustWrongScreen({Key? key}) : super(key: key);
  @override
  State<MustWrongScreen> createState() => _MustWrongScreenState();
}

class _MustWrongScreenState extends State<MustWrongScreen> {
  bool _isLoggedIn = false;
  bool _hasAccess = false;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    final loggedIn = await AuthService().isLoggedIn();
    if (!loggedIn) {
      setState(() {
        _isLoggedIn = false;
      });
      return;
    }
    final vip = await AuthService().getVipDays();
    setState(() {
      _isLoggedIn = true;
      _hasAccess = vip > 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoggedIn) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('必错题 - Question Bank'),
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('请先登录')),
      );
    }
    if (!_hasAccess) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('必错题 - Question Bank'),
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('请成为VIP后使用此功能')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('必错题 - Question Bank'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: const Center(child: Text('VIP内容开发中...')),
    );
  }
}