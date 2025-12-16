import 'package:flutter/material.dart';
import 'package:duclean/res/Constants.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';


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
            left: 10, right: 10, top: 5,
            bottom: 5 + MediaQuery.of(ctx).viewInsets.bottom,
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

// 게이지 그래프
Future<int?> showDialRegisterEditor({
  required BuildContext context,
  required String title,
  required IconData icon,
  required int address,
  required int initialValue,
  required Future<bool> Function(int address, int value) writeRegister,
  required int min,
  required int max,
  int step = 1,
  String unit = '',
  Color accentColor = Colors.blue,
})
async {
  assert(min <= max);
  int clamp(int v) => v < min ? min : (v > max ? max : v);
  int snap(int v) {
    if (v >= max) return max;
    if (v <= min) return min;
    final q = ((v - min) / step).round();           // 가장 가까운 격자
    final snapped = min + q * step;
    return snapped.clamp(min, max);                  // 최종 경계 보정
  }

  int current = snap(clamp(initialValue));
  String? error;

  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 10, right: 10, top: 8,
            bottom: 8 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              Future<void> _openNumericEditor() async {
                final controller = TextEditingController(text: current.toString());
                String? localErr;
                final updated = await showDialog<int>(
                  context: ctx,
                  builder: (dctx) {
                    return StatefulBuilder(
                      builder: (dctx, setDialog) {
                        return AlertDialog(
                          title: const Text('값 입력', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(
                                controller: controller,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  hintText: '$min ~ $max$unit',
                                  errorText: localErr,
                                  isDense: true,
                                  border: const OutlineInputBorder(),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: accentColor),
                                  ),
                                ),
                              ),

                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dctx),
                              child: Text('취소', style: TextStyle(color: AppColor.duBlue),),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: accentColor),
                              onPressed: () {
                                final parsed = int.tryParse(controller.text.trim());
                                if (parsed == null) {
                                  setDialog(() => localErr = '정수를 입력하세요.');
                                  return;
                                }
                                Navigator.pop(dctx, snap(clamp(parsed)));
                              },
                              child: const Text('확인'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
                if (updated != null) setLocal(() => current = updated);
              }

              Future<void> onSave() async {
                final ok = await writeRegister(address, current);
                if (!Navigator.of(ctx).mounted) return;
                if (ok) {
                  Navigator.pop<int>(ctx, current);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('설정이 저장되었습니다.')),
                  );
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
                      Icon(icon, color: accentColor),
                      const SizedBox(width: 8),
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text('$min ~ $max$unit',
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ▶ 게이지 + 중앙 오버레이 버튼
                  SizedBox(
                    height: 240,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SfRadialGauge(
                          axes: <RadialAxis>[
                            RadialAxis(
                              minimum: min.toDouble(),
                              maximum: max.toDouble(),
                              showTicks: true,
                              showLabels: false,
                              axisLineStyle: const AxisLineStyle(thickness: 12),
                              pointers: <GaugePointer>[
                                RangePointer(
                                  value: current.toDouble(),
                                  width: 12,
                                  color: accentColor,
                                ),
                                MarkerPointer(
                                  value: current.toDouble(),
                                  enableDragging: true,
                                  onValueChanged: (v) {
                                    final snapped = snap(clamp(v.round()));
                                    setLocal(() => current = snapped);
                                  },
                                  onValueChanging: (args) {
                                    if (args.value < min || args.value > max) {
                                      args.cancel = true;
                                    }
                                  },
                                  markerType: MarkerType.circle,
                                  markerHeight: 22,
                                  markerWidth: 22,
                                  color: accentColor,
                                ),
                              ],
                            ),
                          ],
                        ),

                        // 중앙 값 표시 + 탭 입력 (InkWell 오버레이)
                        SizedBox(
                          width: 140,
                          height: 64,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: _openNumericEditor,
                              child: Center(
                                child: Text(
                                  '$current$unit',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    color: accentColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (error != null) ...[
                    const SizedBox(height: 6),
                    Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],

                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, null),
                        child: Text('취소', style: TextStyle(color: AppColor.duBlue),),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: onSave,
                        style: FilledButton.styleFrom(backgroundColor: AppColor.duBlue),
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
}