import 'package:flutter/material.dart';
import 'package:italian_driving_app/Services/auth_service.dart';
import 'package:italian_driving_app/database/database_helper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CodeRedeemScreen extends StatefulWidget {
  const CodeRedeemScreen({super.key});

  @override
  State<CodeRedeemScreen> createState() => _CodeRedeemScreenState();
}

class _CodeRedeemScreenState extends State<CodeRedeemScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;

  Future<void> _redeem() async {
    final code = _controller.text.trim().toUpperCase();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入兑换码')));
      return;
    }
    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;
      final session = client.auth.currentSession;
      if (session == null) {
        throw Exception('请先登录');
      }
      final resp = await client.functions.invoke(
        'redeem-code',
        body: {'code': code},
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
        },
      );
      final status = resp.status ?? 500;
      final data = resp.data as Map?;
      if (status == 200) {
        final expireAt = data?['expire_at'] as int?;
        if (expireAt != null) {
          final user = client.auth.currentUser;
          if (user != null) {
            await client
                .from('profiles')
                .update({'vip_expire_at': expireAt})
                .eq('user_id', user.id);
          }

          final userId = await AuthService().ensureLocalUser();
          if (userId != null) {
            final now = DateTime.now().millisecondsSinceEpoch;
            final remainingDays =
                ((expireAt - now) / (24 * 3600 * 1000)).ceil();
            await DatabaseHelper.instance
                .updateVipDays(userId, remainingDays);
          }

          final dt = DateTime.fromMillisecondsSinceEpoch(expireAt)
              .toLocal()
              .toString()
              .split(' ')
              .first;
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('兑换成功，有效期至：$dt')));
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('兑换成功')));
        }
      } else {
        final msg = data?['error']?.toString() ?? '兑换失败';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('兑换失败: ${e.toString()}')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('兑换激活码')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: '请输入兑换码',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _redeem,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('兑换'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

