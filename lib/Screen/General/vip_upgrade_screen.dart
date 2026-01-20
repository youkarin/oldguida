import 'package:flutter/material.dart';
import 'package:italian_driving_app/Services/auth_service.dart';

class VipUpgradeScreen extends StatefulWidget {
  const VipUpgradeScreen({Key? key}) : super(key: key);
  @override
  State<VipUpgradeScreen> createState() => _VipUpgradeScreenState();
}

class _VipUpgradeScreenState extends State<VipUpgradeScreen> {
  int _vipDays = 0;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final loggedIn = await AuthService().isLoggedIn();
    if (!loggedIn) {
      setState(() {
        _loggedIn = false;
      });
      return;
    }
    final vip = await AuthService().getVipDays();
    setState(() {
      _loggedIn = true;
      _vipDays = vip;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VIP升级'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: _loggedIn
            ? Text('剩余VIP天数: $_vipDays')
            : const Text('请先登录'),
      ),
    );
  }
}