import 'package:flutter/material.dart';

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final FlutterAppAuth appAuth = FlutterAppAuth();
final FlutterSecureStorage vault = const FlutterSecureStorage();

const AUTH0_DOMAIN = 'dev-cookndx.us.auth0.com';
const AUTH0_CLIENT_ID = 'awnRQ6j3fsUWtOkgmJzY0vP2RNRNtKFt';

const AUTH0_REDIRECT_URI = 'com.cookndx://login-callback';
const AUTH0_ISSUER = 'https://$AUTH0_DOMAIN';

const REFRESH_TOKEN = 'refresh_token';

void main() {
  runApp(CookNDXApp());
}

class Profile extends StatelessWidget {
  final logoutAction;
  final String name;
  final String picture;

  Profile(this.logoutAction, this.name, this.picture);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 150,
          height: 150,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.blue, width: 4.0),
            shape: BoxShape.circle,
            image: DecorationImage(
              fit: BoxFit.fill,
              image: NetworkImage(picture ?? ''),
            ),
          ),
        ),
        SizedBox(height: 24.0),
        Text('Name: $name'),
        SizedBox(height: 48.0),
        RaisedButton(
          onPressed: () {
            logoutAction();
          },
          child: Text('Logout'),
        ),
      ],
    );
  }
}

class Login extends StatelessWidget {
  final loginAction;
  final String loginError;

  const Login(this.loginAction, this.loginError);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        RaisedButton(
          onPressed: () {
            loginAction();
          },
          child: Text('Login'),
        ),
        Text(loginError ?? ''),
      ],
    );
  }
}

class CookNDXApp extends StatefulWidget {
  @override
  _AppState createState() => _AppState();
}

class _AppState extends State<CookNDXApp> {
  bool isBusy = false;
  bool isLoggedIn = false;
  String errorMessage;
  String name;
  String picture;
  DateTime accessTokenExpiry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Login',
      home: Scaffold(
        appBar: AppBar(
          title: Text('CookNDX'),
        ),
        body: Center(
          child: isBusy
              ? CircularProgressIndicator()
              : isLoggedIn
                  ? Profile(logoutAction, name, picture)
                  : Login(loginAction, errorMessage),
        ),
      ),
    );
  }

  Map<String, dynamic> parseIdToken(String idToken) {
    final parts = idToken.split(r'.');
    assert(parts.length == 3);

    return decode(parts[1]);
  }

  decode(String toDecode) => jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(toDecode))));

  Future<Map> getUserDetails(String accessToken) async {
    final url = 'https://$AUTH0_DOMAIN/userinfo';
    final authzBearer = {'Authorization': 'Bearer $accessToken'};
    final response = await http.get(url, headers: authzBearer);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get user details');
    }
  }

  void handleLoginSuccess(AuthorizationTokenResponse result) async {
    accessTokenExpiry = result.accessTokenExpirationDateTime;
    final idToken = parseIdToken(result.idToken);
    final profile = await getUserDetails(result.accessToken);

    await vault.write(key: REFRESH_TOKEN, value: result.refreshToken);

    setState(() {
      isBusy = false;
      isLoggedIn = true;
      name = idToken['name'];
      picture = profile['picture'];
    });
  }

  Future<void> loginAction() async {
    setState(() {
      isBusy = true;
      errorMessage = '';
    });

    try {
      final AuthorizationTokenResponse response = await appAuth.authorizeAndExchangeCode(
          AuthorizationTokenRequest(
              AUTH0_CLIENT_ID,
              AUTH0_REDIRECT_URI,
              issuer: 'https://$AUTH0_DOMAIN',
              scopes: ['openid', 'profile', 'offline_access'],
              // ignore any existing session; force interactive login prompt
              promptValues: ['login']
          )
      );

      handleLoginSuccess(response);
    } catch (e, s) {
      print('login error: $s - stack: $s');

      setState(() {
        isBusy = false;
        isLoggedIn = false;
        errorMessage = e.toString();
      });
    }
  }

  void logoutAction() async {
    await vault.delete(key: REFRESH_TOKEN);
    setState(() {
      isLoggedIn = false;
      isBusy = false;
    });
  }

  @override
  void initState() {
    initAction();
    super.initState();
  }

  void initAction() async {
    if (isAccessTokenValid()) {
      return;
    }

    final refreshToken = await vault.read(key: REFRESH_TOKEN);
    if (null == refreshToken) {
      return;
    }

    setState(() => isBusy = true);
    
    try {
      final response = await appAuth.token(TokenRequest(
          AUTH0_CLIENT_ID,
          AUTH0_REDIRECT_URI,
          issuer: 'https://$AUTH0_DOMAIN',
          refreshToken: refreshToken
      ));
      
      handleLoginSuccess(response);
    } catch (e, s) {
      print('error on refresh token: $e - stack: $s');
      logoutAction();
    }
  }

  bool isAccessTokenValid() {
    return null != accessTokenExpiry &&
        DateTime.now().toUtc().isBefore(accessTokenExpiry);
  }
}

