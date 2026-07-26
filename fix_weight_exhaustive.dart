import 'package:file/local.dart';
import 'package:file/file.dart';
import 'dart:io';

void main() async {
  final fs = LocalFileSystem();
  final inputFile = fs.file(r'e:\Enything\supabase\migrations\20271125000008_100x_unit_type_weight_fix.sql');
  final content = await inputFile.readAsString();

  final regex = RegExp(r'(CREATE OR REPLACE FUNCTION public\.place_orders_transaction.*?\$function\$\n;)', dotAll: true);
  final match = regex.firstMatch(content);
  
  if (match == null) {
    print("Function not found");
    exit(1);
  }
  
  String funcContent = match.group(1)!;
  
  final oldLoop = '''  FOR v_item IN SELECT y.quantity, p.weight_per_unit, p.unit_type 
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

  final newLoop = '''  FOR v_item IN SELECT y.quantity, p.weight_per_unit, p.unit_type 
                FROM jsonb_to_recordset(p_items) AS y(product_id uuid, quantity int)
                JOIN products p ON p.id = y.product_id LOOP
    IF v_item.weight_per_unit IS NULL THEN
      -- Default standard weight if the seller completely omitted it
      v_total_weight_kg := v_total_weight_kg + (0.5 * v_item.quantity);
    ELSE
      -- Exhaustive 100x Unit Resolution
      IF LOWER(TRIM(v_item.unit_type)) IN ('grams', 'gram', 'g', 'ml', 'milliliter', 'milliliters') THEN
        -- Convert smaller metrics to kg directly
        v_total_weight_kg := v_total_weight_kg + ((v_item.weight_per_unit / 1000.0) * v_item.quantity);
      ELSIF LOWER(TRIM(v_item.unit_type)) IN ('kg', 'kilogram', 'kilograms', 'l', 'liter', 'liters') THEN
        -- 1:1 direct volume/weight mapping
        v_total_weight_kg := v_total_weight_kg + (v_item.weight_per_unit * v_item.quantity);
      ELSIF LOWER(TRIM(v_item.unit_type)) IN ('pieces', 'piece', 'pcs', 'pc') THEN
        -- A 'piece' could weigh anything. We trust the weight_per_unit as the per-piece kg weight.
        v_total_weight_kg := v_total_weight_kg + (v_item.weight_per_unit * v_item.quantity);
      ELSE
        -- Absolute ultimate fallback to prevent crash on weird corrupted strings
        v_total_weight_kg := v_total_weight_kg + (v_item.weight_per_unit * v_item.quantity);
      END IF;
    END IF;
  END LOOP;''';

  if (!funcContent.contains(oldLoop)) {
    print("Old loop not found in function");
    exit(1);
  }

  funcContent = funcContent.replaceAll(oldLoop, newLoop);

  final finalContent = '''-- =============================================================================
-- Migration: 20271125000009_100x_unit_type_exhaustive_fix.sql
-- Description: ADDITIVE ONLY — CREATE OR REPLACE FUNCTION only.
--              Extends the previous weight fix to exhaustively cover EVERY single
--              possible unit string present in the Flutter app or legacy DB rows:
--              ('liter', 'grams', 'gram', 'ml', 'kg', 'pieces', 'piece', etc.)
-- =============================================================================

''' + funcContent + '\n';

  final outputFile = fs.file(r'e:\Enything\supabase\migrations\20271125000009_100x_unit_type_exhaustive_fix.sql');
  await outputFile.writeAsString(finalContent);

  print("Migration created successfully.");
}
