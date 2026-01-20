import 'dart:async';
import 'package:flutter/material.dart';
import 'package:italian_driving_app/Services/auth_service.dart';
import 'package:italian_driving_app/Services/sync_service.dart';
import 'package:italian_driving_app/utils/debug_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class LoginRegisterScreen extends StatefulWidget {
  const LoginRegisterScreen({Key? key}) : super(key: key);

  @override
  State<LoginRegisterScreen> createState() => _LoginRegisterScreenState();
}

class _LoginRegisterScreenState extends State<LoginRegisterScreen> {
  bool isLogin = true;
  final _formKey = GlobalKey<FormState>();
  String username = '';
  String password = '';
  String confirmPassword = '';
  String email = '';
  bool _hidePassword = true;
  bool _hideConfirmPassword = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isLogin ? '登录' : '注册'),
        backgroundColor: Color(0xFF667eea),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isLogin ? '账号登录' : '新用户注册',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.indigo),
                    ),
                    SizedBox(height: 24),

                    if (isLogin)
                      TextFormField(
                        decoration: InputDecoration(
                          labelText: '邮箱',
                          prefixIcon: Icon(Icons.email),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (val) {
                          if (val == null || val.isEmpty) return '请输入邮箱';
                          if (!val.contains('@')) return '邮箱格式错误';
                          return null;
                        },
                        onChanged: (val) => email = val.trim(),
                      )
                    else
                      Column(
                        children: [
                          TextFormField(
                            decoration: InputDecoration(
                              labelText: '用户名',
                              prefixIcon: Icon(Icons.person),
                              border: OutlineInputBorder(),
                            ),
                            validator: (val) => val == null || val.isEmpty ? '请输入用户名' : null,
                            onChanged: (val) => username = val.trim(),
                          ),
                          SizedBox(height: 18),
                          TextFormField(
                            decoration: InputDecoration(
                              labelText: '邮箱',
                              prefixIcon: Icon(Icons.email),
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            validator: (val) {
                              if (val == null || val.isEmpty) return '请输入邮箱';
                              if (!val.contains('@')) return '邮箱格式错误';
                              return null;
                            },
                            onChanged: (val) => email = val.trim(),
                          ),
                          SizedBox(height: 18),
                        ],
                      ),

                    TextFormField(
                      decoration: InputDecoration(
                        labelText: '密码',
                        prefixIcon: Icon(Icons.lock),
                        border: OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_hidePassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () {
                            setState(() {
                              _hidePassword = !_hidePassword;
                            });
                          },
                        ),
                      ),
                      obscureText: _hidePassword,
                      validator: (val) => val == null || val.length < 6 ? '密码至少6位' : null,
                      onChanged: (val) => password = val,
                    ),
                    SizedBox(height: 18),

                    if (!isLogin)
                      TextFormField(
                        decoration: InputDecoration(
                          labelText: '确认密码',
                          prefixIcon: Icon(Icons.lock_outline),
                          border: OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(_hideConfirmPassword ? Icons.visibility_off : Icons.visibility),
                            onPressed: () {
                              setState(() {
                                _hideConfirmPassword = !_hideConfirmPassword;
                              });
                            },
                          ),
                        ),
                        obscureText: _hideConfirmPassword,
                        validator: (val) => val != password ? '两次输入的密码不一致' : null,
                        onChanged: (val) => confirmPassword = val,
                      ),

                    SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        child: Text(isLogin ? '登录' : '注册'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF667eea),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _submit,
                      ),
                    ),
                    SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          isLogin = !isLogin;
                        });
                      },
                      child: Text(isLogin ? '没有账号？注册' : '已有账号？登录'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final client = Supabase.instance.client;

    if (isLogin) {
      try {
        await client.auth
            .signInWithPassword(email: email, password: password);
        final user = client.auth.currentUser;
        if (user == null) {
          throw AuthException('登录失败');
        }
        var profile = await client
            .from('profiles')
            .select('username, email')
            .eq('user_id', user.id)
            .maybeSingle();
        if (profile == null) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final defaultUsername =
              (user.userMetadata?['username'] as String?) ??
              user.email?.split('@').first ??
              '';
          await client.from('profiles').insert({
            'user_id': user.id,
            'username': defaultUsername,
            'email': user.email,
            'uuid': const Uuid().v4(),
            'created_at': now,
            'updated_at': now,
          });
          profile = {
            'username': defaultUsername,
            'email': user.email,
          };
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('登录成功')));
        await AuthService().login(profile['username'] ?? '');
        Navigator.pop(context, profile);
        unawaited(() async {
          final vipDays = await AuthService().getVipDays();
          if (vipDays > 0) {
            final ok = await SyncService.syncAll();
            await DebugUtils.showSnackBar(
                ok ? '同步完成' : '同步失败',
                isError: !ok);
          }
        }());
      } on AuthException catch (e) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      } on PostgrestException catch (e) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('登录失败: ${e.message}')));
      } catch (e) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('登录失败: ${e.toString()}')));
      }
    } else {
      try {
        final authRes = await client.auth
            .signUp(email: email, password: password, data: {'username': username});
        final userId = authRes.user?.id;
        if (userId == null) throw AuthException('注册失败');

        // 如果需要邮箱验证，Supabase 不会返回 session，此时跳过 profile 插入
        if (authRes.session == null) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('注册成功，请验证邮箱后登录')));
          setState(() => isLogin = true);
          return;
        }

        final now = DateTime.now().millisecondsSinceEpoch;
        await client.from('profiles').insert({
          'user_id': userId,
          'username': username,
          'email': email,
          'uuid': const Uuid().v4(),
          'created_at': now,
          'updated_at': now,
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('注册成功，请登录')));
        setState(() => isLogin = true);
      } on AuthException catch (e) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      } on PostgrestException catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('注册失败: ${e.message}')));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('注册失败: ${e.toString()}')));
      }
    }
  }
}
