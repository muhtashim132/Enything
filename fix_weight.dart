import 'package:file/local.dart';
import 'package:file/file.dart';
import 'dart:io';

void main() async {
  const fs = LocalFileSystem();
  final inputFile = fs.file(
      r'e:\Enything\supabase\migrations\20271125000007_100x_critical_bug_fixes.sql');
  final content = await inputFile.readAsString();

  final regex = RegExp(
      r'(CREATE OR REPLACE FUNCTION public\.place_orders_transaction.*?\$function\$\n;)',
      dotAll: true);
  final match = regex.firstMatch(content);

  if (match == null) {
    print("Function not found");
    exit(1);
  }

  String funcContent = match.group(1)!;

  const oldLoop = '''  FOR v_item IN SELECT y.quantity, p.weight_per_unit 
                FROM jsonb_to_recordset(p_items) AS y(product_id uuid, quantity int)
                JOIN products p ON p.id = y.product_id LOOP
    v_total_weight_kg := v_total_weight_kg + (COALESCE(v_item.weight_per_unit, 0.5) * v_item.quantity);
  END LOOP;''';

  const newLoop =
      '''  FOR v_item IN SELECT y.quantity, p.weight_per_unit, p.unit_type 
                FROM jsonb_to_recordset(p_items) AS y(product_id uuid, quantity int)
                JOIN products p ON p.id = y.product_id LOOP
    IF v_item.weight_per_unit IS NULL THEN
      v_total_weight_kg := v_total_weight_kg + (0.5 * v_item.quantity);
    ELSE
      IF LOWER(v_item.unit_type) IN ('grams', 'g', 'ml') THEN
        v_total_weight_kg := v_total_weight_kg + ((v_item.weight_per_unit / 1000.0) * v_item.quantity);
      ELSIF LOWER(v_item.unit_type) IN ('kg', 'l', 'liters') THEN
        v_total_weight_kg := v_total_weight_kg + (v_item.weight_per_unit * v_item.quantity);
      ELSE
        -- fallback for 'pieces' or other unknown units with explicit numeric weight assigned
        v_total_weight_kg := v_total_weight_kg + (v_item.weight_per_unit * v_item.quantity);
      END IF;
    END IF;
  END LOOP;''';

  if (!funcContent.contains(oldLoop)) {
    print("Old loop not found in function");
    exit(1);
  }

  funcContent = funcContent.replaceAll(oldLoop, newLoop);

  final finalContent =
      '''-- =============================================================================
-- Migration: 20271125000008_100x_unit_type_weight_fix.sql
-- Description: ADDITIVE ONLY — CREATE OR REPLACE FUNCTION only.
--              Fixes the 800kg checkout bug by respecting product unit_type
--              when aggregating cart weight (grams/ml to kg conversion).
-- =============================================================================

''' +
          funcContent +
          '\n';

  final outputFile = fs.file(
      r'e:\Enything\supabase\migrations\20271125000008_100x_unit_type_weight_fix.sql');
  await outputFile.writeAsString(finalContent);

  print("Migration created successfully.");
}
