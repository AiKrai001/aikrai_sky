import 'package:flutter/material.dart';

import '../models/address_record.dart';
import '../services/address_database_service.dart';
import 'add_location_page.dart';

const _pageBackgroundColor = Color(0xFFF9F8FC);
const _primaryTextColor = Color(0xFF202124);
const _accentColor = Color(0xFFD81B60);
const _iconColor = Color(0xFF24466E);
const _secondaryTextColor = Color(0xFF7C8087);
const _dividerColor = Color(0xFFE1E1E6);

/// 位置管理页面。
///
/// 用于手动添加、删除和调整首页位置顺序。首页返回后根据本页返回值刷新位置列表。
class LocationManagementPage extends StatefulWidget {
  const LocationManagementPage({
    super.key,
    required this.currentLocatedAddressId,
    required this.currentLocatedAddress,
  });

  final int? currentLocatedAddressId;
  final AddressRecord? currentLocatedAddress;

  @override
  State<LocationManagementPage> createState() => _LocationManagementPageState();
}

class _LocationManagementPageState extends State<LocationManagementPage> {
  List<AddressRecord> _records = const [];
  bool _isLoading = true;
  bool _hasChanged = false;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final records = await AddressDatabaseService.instance
        .fetchAllAddressRecords();
    if (!mounted) {
      return;
    }

    setState(() {
      _records = records;
      _isLoading = false;
    });
  }

  Future<void> _openAddLocationPage() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const AddLocationPage()),
    );
    if (added != true) {
      return;
    }

    _hasChanged = true;
    await _loadRecords();
    _showSnackBar('位置已添加');
  }

  Future<void> _handleReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    final reorderedRecords = [..._records];
    final movedRecord = reorderedRecords.removeAt(oldIndex);
    reorderedRecords.insert(newIndex, movedRecord);

    setState(() {
      _records = [
        for (var index = 0; index < reorderedRecords.length; index += 1)
          reorderedRecords[index].copyWith(sortOrder: index),
      ];
    });

    try {
      await AddressDatabaseService.instance.updateAddressSortOrders(_records);
      _hasChanged = true;
    } catch (error) {
      _showSnackBar('保存位置顺序失败：$error');
      await _loadRecords();
    }
  }

  Future<void> _deleteRecord(AddressRecord record) async {
    final addressId = record.id;
    if (addressId == null) {
      _showSnackBar('删除失败：位置缺少 id');
      return;
    }

    setState(() {
      _records = _records.where((item) => item.id != addressId).toList();
    });

    try {
      await AddressDatabaseService.instance.deleteAddressById(addressId);
      await AddressDatabaseService.instance.updateAddressSortOrders(_records);
      _hasChanged = true;
      _showSnackBar('${_locationTitle(record)}已删除');
    } catch (error) {
      _showSnackBar('删除位置失败：$error');
      await _loadRecords();
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

  void _popPage() {
    Navigator.of(context).pop(_hasChanged);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        _popPage();
      },
      child: Scaffold(
        backgroundColor: _pageBackgroundColor,
        appBar: AppBar(
          backgroundColor: _pageBackgroundColor,
          foregroundColor: _primaryTextColor,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            tooltip: '返回',
            icon: const Icon(Icons.arrow_back, size: 30),
            onPressed: _popPage,
          ),
          title: const Text(
            '管理城市',
            style: TextStyle(
              color: _primaryTextColor,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            IconButton(
              tooltip: '添加位置',
              icon: const Icon(Icons.add, size: 28),
              onPressed: _openAddLocationPage,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Stack(
            children: [
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else if (_records.isEmpty)
                const Center(
                  child: Text(
                    '暂无位置',
                    style: TextStyle(color: _secondaryTextColor, fontSize: 15),
                  ),
                )
              else
                ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                  buildDefaultDragHandles: false,
                  itemCount: _records.length,
                  onReorder: _handleReorder,
                  itemBuilder: (context, index) {
                    final record = _records[index];
                    final isCurrentLocation = _isCurrentLocation(record);
                    return Dismissible(
                      key: ValueKey('location-${record.id ?? index}'),
                      direction: DismissDirection.endToStart,
                      background: const _DeleteBackground(),
                      onDismissed: (_) => _deleteRecord(record),
                      child: _LocationManageRow(
                        record: record,
                        isCurrentLocation: isCurrentLocation,
                        onDelete: () => _deleteRecord(record),
                        dragHandle: ReorderableDragStartListener(
                          index: index,
                          child: const SizedBox.square(
                            dimension: 32,
                            child: Icon(
                              Icons.drag_handle,
                              color: _secondaryTextColor,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isCurrentLocation(AddressRecord record) {
    final addressId = record.id;
    if (addressId != null &&
        widget.currentLocatedAddressId != null &&
        addressId == widget.currentLocatedAddressId) {
      return true;
    }

    final currentDistrict = widget.currentLocatedAddress?.district.trim();
    return currentDistrict != null &&
        currentDistrict.isNotEmpty &&
        record.district.trim() == currentDistrict;
  }
}

class _LocationManageRow extends StatelessWidget {
  const _LocationManageRow({
    required this.record,
    required this.isCurrentLocation,
    required this.dragHandle,
    required this.onDelete,
  });

  final AddressRecord record;
  final bool isCurrentLocation;
  final Widget dragHandle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _pageBackgroundColor,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _dividerColor, width: 1)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              dragHandle,
              const SizedBox(width: 10),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            _locationTitle(record),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _accentColor,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (isCurrentLocation) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.location_on,
                            color: _iconColor,
                            size: 17,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _locationSubtitle(record),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _secondaryTextColor,
                        fontSize: 15,
                        height: 1.25,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox.square(
                dimension: 36,
                child: IconButton(
                  tooltip: '删除位置',
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.delete_outline,
                    color: _secondaryTextColor,
                    size: 22,
                  ),
                  onPressed: onDelete,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 22),
      color: const Color(0xFFE53935),
      child: const Icon(Icons.delete_outline, color: Colors.white, size: 30),
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
  final parts = <String>[];
  for (final part in [record.city, record.province]) {
    final value = part.trim();
    if (value.isEmpty || parts.contains(value)) {
      continue;
    }
    parts.add(value);
  }
  if (parts.isNotEmpty) {
    return parts.join('，');
  }
  return '${record.latitude.toStringAsFixed(4)}，${record.longitude.toStringAsFixed(4)}';
}
