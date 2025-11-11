import 'package:flutter/material.dart';
import 'package:duclean/res/Constants.dart';
import 'package:material_symbols_icons/symbols.dart';


// 숫자 입력 필드
Future<int?> showRegisterNumberEditor({
  required BuildContext context,
  required String title,
  required IconData icon,
  required int address,
  required int initialValue,
  required Future<bool> Function(int address, int value) writeRegister,
  int min = 0,
  int max = 32000,
  Color? accentColor,
  String hintText = '0 ~ 32000',
})
async {
  final controller = TextEditingController(text: initialValue.toString());
  String? error;
  final Color ac = accentColor ?? Theme.of(context).colorScheme.primary;

  final saved = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              Future<void> onSave() async {
                final parsed = int.tryParse(controller.text.trim());
                if (parsed == null || parsed < min || parsed > max) {
                  setLocal(() => error = '$min~$max 사이의 정수를 입력하세요.');
                  return;
                }
                final ok = await writeRegister(address, parsed);
                if (ok) {
                  Navigator.pop<int>(ctx, parsed); // 저장된 값 반환
                } else {
                  setLocal(() => error = '저장 실패');
                }
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: ac),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    cursorColor: ac,
                    decoration: InputDecoration(
                      hintText: hintText,
                      errorText: error,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: ac),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: ac),
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('취소'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: ac),
                        onPressed: onSave,
                        child: const Text('저장'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
  return saved; // null(취소/실패) 또는 저장된 값
}


// 라디오 선택 필드
Future<T?> showRadioPicker<T>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required T groupValue,
  required String Function(T) labelOf,
})
async {
  return await showModalBottomSheet<T>(
    context: context,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 8),
              RadioGroup<T>(
                groupValue: groupValue,
                onChanged: (v) {
                  Navigator.pop(ctx, v);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: options.map((opt) {
                    return RadioListTile<T>(
                      value: opt,
                      title: Text(labelOf(opt)),
                      activeColor: AppColor.duBlue,
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

// 토글 필드
Future<void> applyRegisterToggle({
  required BuildContext context,
  required bool newValue,                   // 스위치가 바뀐 값
  required int address,                     // 레지스터 주소
  required writeRegister,
  required ValueChanged<bool> setLocalValue,// setState(() => state = v)
  String errorText = '설정 저장 실패',
  bool optimistic = true,
}) async {
  if (optimistic) {
    setLocalValue(newValue);
  }
  final ok = await writeRegister(address, newValue ? 1 : 0);
  if (!context.mounted) return;

  if (!ok) {
    if (optimistic) {
      setLocalValue(!newValue); // 롤백
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(errorText)),
    );
  }
}