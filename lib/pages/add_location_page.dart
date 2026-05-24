import 'dart:async';

import 'package:flutter/material.dart';

import '../models/address_record.dart';
import '../services/location_address_service.dart';

/// 添加城市页面。
///
/// 用户输入关键字后先展示多个候选地址，点击具体候选项后才保存到位置表。
class AddLocationPage extends StatefulWidget {
  const AddLocationPage({super.key});

  @override
  State<AddLocationPage> createState() => _AddLocationPageState();
}

class _AddLocationPageState extends State<AddLocationPage> {
  final _controller = TextEditingController();
  final _locationAddressService = const LocationAddressService();

  Timer? _debounceTimer;
  List<AddressRecord> _options = const [];
  String _message = '输入城市、区县或详细地址';
  bool _isSearching = false;
  bool _isSaving = false;
  int _searchRequestId = 0;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _handleQueryChanged(String value) {
    _debounceTimer?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _options = const [];
        _message = '输入城市、区县或详细地址';
        _isSearching = false;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 450), () {
      _search(query);
    });
  }

  Future<void> _search(String query) async {
    final requestId = _searchRequestId + 1;
    _searchRequestId = requestId;
    setState(() {
      _isSearching = true;
      _message = '正在搜索...';
    });

    try {
      final options = await _locationAddressService.searchAddressOptions(query);
      if (!mounted || requestId != _searchRequestId) {
        return;
      }

      setState(() {
        _options = options;
        _message = options.isEmpty ? '没有搜索到匹配的位置' : '';
      });
    } on LocationAddressException catch (error) {
      if (!mounted || requestId != _searchRequestId) {
        return;
      }
      setState(() {
        _options = const [];
        _message = error.message;
      });
    } catch (error) {
      if (!mounted || requestId != _searchRequestId) {
        return;
      }
      setState(() {
        _options = const [];
        _message = '搜索失败：$error';
      });
    } finally {
      if (mounted && requestId == _searchRequestId) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _saveOption(AddressRecord option) async {
    if (_isSaving) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await _locationAddressService.saveAddress(option);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on LocationAddressException catch (error) {
      _showSnackBar(error.message);
    } catch (error) {
      _showSnackBar('保存位置失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _clearQuery() {
    _controller.clear();
    _handleQueryChanged('');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F8FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF9F8FC),
        foregroundColor: const Color(0xFF202124),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back, size: 30),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: const Text(
          '添加城市',
          style: TextStyle(
            color: Color(0xFF202124),
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: _SearchBox(
                controller: _controller,
                onChanged: _handleQueryChanged,
                onSubmitted: _search,
                onClear: _clearQuery,
              ),
            ),
            if (_isSearching)
              const LinearProgressIndicator(minHeight: 2)
            else
              const SizedBox(height: 2),
            Expanded(
              child: _options.isEmpty
                  ? Center(
                      child: Text(
                        _message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF8A8A8A),
                          fontSize: 15,
                        ),
                      ),
                    )
                  : ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                      itemCount: _options.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: Color(0xFFE1E1E6)),
                      itemBuilder: (context, index) {
                        final option = _options[index];
                        return _SearchOptionTile(
                          option: option,
                          isSaving: _isSaving,
                          onTap: () => _saveOption(option),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        return TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: const TextStyle(fontSize: 18, color: Color(0xFF202124)),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, size: 26),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清空',
                    icon: const Icon(Icons.close, size: 26),
                    onPressed: onClear,
                  ),
            hintText: '输入城市、区县或详细地址',
            hintStyle: const TextStyle(color: Color(0xFF7C8087)),
            filled: false,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
            enabledBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF24466E), width: 2.4),
              borderRadius: BorderRadius.zero,
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF24466E), width: 2.4),
              borderRadius: BorderRadius.zero,
            ),
          ),
        );
      },
    );
  }
}

class _SearchOptionTile extends StatelessWidget {
  const _SearchOptionTile({
    required this.option,
    required this.isSaving,
    required this.onTap,
  });

  final AddressRecord option;
  final bool isSaving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isSaving ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.location_on, color: Color(0xFF24466E), size: 30),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _locationTitle(option),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFD81B60),
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _locationSubtitle(option),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF7C8087),
                      fontSize: 15,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _locationTitle(AddressRecord record) {
  if (record.district.isNotEmpty) {
    return record.district;
  }
  if (record.city.isNotEmpty) {
    return record.city;
  }
  if (record.province.isNotEmpty) {
    return record.province;
  }
  return record.detailAddress;
}

String _locationSubtitle(AddressRecord record) {
  final detailAddress = record.detailAddress.trim();
  if (detailAddress.isNotEmpty) {
    return detailAddress;
  }

  final parts = <String>[];
  for (final part in [record.province, record.city]) {
    final value = part.trim();
    if (value.isEmpty || parts.contains(value)) {
      continue;
    }
    parts.add(value);
  }
  if (parts.isNotEmpty) {
    return parts.join('');
  }
  return '${record.latitude.toStringAsFixed(4)}，${record.longitude.toStringAsFixed(4)}';
}
