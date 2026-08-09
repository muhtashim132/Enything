import 'package:supabase/supabase.dart';
import 'dart:convert';
import 'dart:io';

void main() async {
  final supabaseUrl = const String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://vjymswrnyvggcplgkzqh.supabase.co');
  final supabaseKey = const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'eyJhb...'); 
  // Wait, I can't easily get the anon key from the env without knowing it.
  // BUT I can just read it from lib/supabase/supabase_config.dart!
}
