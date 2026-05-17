import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/caiyun_weather_response.dart';
import '../models/weather_record.dart';
import '../services/address_database_service.dart';

/// 天气数据表数据查看页面。
///
/// 支持按天气日期筛选、分页查看，并在固定高度窗口中完整滚动展示原始响应 JSON。
class WeatherRecordsPage extends StatefulWidget {
  const WeatherRecordsPage({super.key});

  @override
  State<WeatherRecordsPage> createState() => _WeatherRecordsPageState();
}

class _WeatherRecordsPageState extends State<WeatherRecordsPage> {
  static const _pageSize = 5;

  DateTime? _selectedDate;
  int _currentPage = 0;
  int _totalCount = 0;
  bool _isLoading = false;
  List<WeatherRecord> _records = const [];

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  /// 加载当前筛选条件和页码对应的数据。
  Future<void> _loadPage() async {
    setState(() {
      _isLoading = true;
    });

    final totalCount = await AddressDatabaseService.instance
        .countWeatherRecords(date: _selectedDate);
    final records = await AddressDatabaseService.instance.fetchWeatherRecords(
      date: _selectedDate,
      limit: _pageSize,
      offset: _currentPage * _pageSize,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _totalCount = totalCount;
      _records = records;
      _isLoading = false;
    });
  }

  /// 选择需要查询的天气日期。
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1),
    );

    if (pickedDate == null) {
      return;
    }

    setState(() {
      _selectedDate = pickedDate;
      _currentPage = 0;
    });
    await _loadPage();
  }

  /// 清空日期筛选，恢复查询全部天气记录。
  Future<void> _clearDateFilter() async {
    setState(() {
      _selectedDate = null;
      _currentPage = 0;
    });
    await _loadPage();
  }

  Future<void> _goToPreviousPage() async {
    if (_currentPage == 0) {
      return;
    }

    setState(() {
      _currentPage -= 1;
    });
    await _loadPage();
  }

  Future<void> _goToNextPage() async {
    if (!_hasNextPage) {
      return;
    }

    setState(() {
      _currentPage += 1;
    });
    await _loadPage();
  }

  bool get _hasNextPage => (_currentPage + 1) * _pageSize < _totalCount;

  String get _dateFilterText {
    final selectedDate = _selectedDate;
    if (selectedDate == null) {
      return '全部日期';
    }
    return WeatherRecord.formatWeatherDate(selectedDate);
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = _totalCount == 0
        ? 1
        : ((_totalCount - 1) ~/ _pageSize) + 1;

    return Scaffold(
      appBar: AppBar(title: const Text('天气数据表数据')),
      body: SafeArea(
        child: Column(
          children: [
            _TableFilterBar(
              dateText: _dateFilterText,
              totalCount: _totalCount,
              currentPage: _currentPage,
              pageCount: pageCount,
              onPickDate: _pickDate,
              onClearDate: _clearDateFilter,
              hasDateFilter: _selectedDate != null,
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _loadPage,
                      child: _records.isEmpty
                          ? const _EmptyScrollableMessage(message: '暂无天气数据')
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _records.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                return _WeatherRecordCard(
                                  record: _records[index],
                                );
                              },
                            ),
                    ),
            ),
            _PaginationBar(
              currentPage: _currentPage,
              pageCount: pageCount,
              onPrevious: _goToPreviousPage,
              onNext: _goToNextPage,
              canGoPrevious: _currentPage > 0,
              canGoNext: _hasNextPage,
            ),
          ],
        ),
      ),
    );
  }
}

/// 天气记录卡片，完整展示天气表字段和原始响应。
class _WeatherRecordCard extends StatelessWidget {
  const _WeatherRecordCard({required this.record});

  final WeatherRecord record;

  @override
  Widget build(BuildContext context) {
    final parsedWeather = _tryParseWeather();
    final rows = [
      ('Id', '${record.id ?? ''}'),
      ('地址Id', '${record.addressId}'),
      ('天气日期', record.weatherDate),
      ('创建时间', record.createdAt.toLocal().toString()),
      ('更新时间', record.updatedAt.toLocal().toString()),
      if (parsedWeather != null) ...[
        ('接口状态', parsedWeather.status),
        ('API版本', parsedWeather.apiVersion),
        ('语言/单位', '${parsedWeather.lang} / ${parsedWeather.unit}'),
        ('时区', parsedWeather.timezone),
        ('服务器时间', '${parsedWeather.serverTime}'),
        ('接口位置', parsedWeather.location.join(', ')),
        ('预报摘要', parsedWeather.result.forecastKeypoint),
      ],
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SelectableText('${row.$1}：${row.$2}'),
              ),
            const SizedBox(height: 8),
            Text('请求原始响应', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _RawResponseViewer(rawResponse: record.rawResponse),
          ],
        ),
      ),
    );
  }

  /// 解析天气响应；如果历史数据格式异常，页面仍继续展示原始响应。
  CaiyunWeatherResponse? _tryParseWeather() {
    try {
      return record.weather;
    } on FormatException {
      return null;
    }
  }
}

/// 固定高度原始响应查看器。
///
/// 外层限定高度，内层垂直滚动；文本使用 SelectableText，便于复制完整 JSON。
class _RawResponseViewer extends StatelessWidget {
  const _RawResponseViewer({required this.rawResponse});

  final String rawResponse;

  @override
  Widget build(BuildContext context) {
    final formattedResponse = _formatJson(rawResponse);

    return Container(
      height: 260,
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            formattedResponse,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ),
      ),
    );
  }

  /// 将紧凑 JSON 格式化为易读文本；格式异常时直接返回原始内容。
  String _formatJson(String rawResponse) {
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(jsonDecode(rawResponse));
    } on FormatException {
      return rawResponse;
    }
  }
}

/// 表格筛选栏。
class _TableFilterBar extends StatelessWidget {
  const _TableFilterBar({
    required this.dateText,
    required this.totalCount,
    required this.currentPage,
    required this.pageCount,
    required this.onPickDate,
    required this.onClearDate,
    required this.hasDateFilter,
  });

  final String dateText;
  final int totalCount;
  final int currentPage;
  final int pageCount;
  final VoidCallback onPickDate;
  final VoidCallback onClearDate;
  final bool hasDateFilter;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('日期：$dateText'),
            Text('总数：$totalCount'),
            Text('页码：${currentPage + 1}/$pageCount'),
            OutlinedButton.icon(
              onPressed: onPickDate,
              icon: const Icon(Icons.calendar_month),
              label: const Text('按日查询'),
            ),
            if (hasDateFilter)
              OutlinedButton.icon(
                onPressed: onClearDate,
                icon: const Icon(Icons.clear),
                label: const Text('清空'),
              ),
          ],
        ),
      ),
    );
  }
}

/// 分页操作栏。
class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.currentPage,
    required this.pageCount,
    required this.onPrevious,
    required this.onNext,
    required this.canGoPrevious,
    required this.canGoNext,
  });

  final int currentPage;
  final int pageCount;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final bool canGoPrevious;
  final bool canGoNext;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: canGoPrevious ? onPrevious : null,
                icon: const Icon(Icons.chevron_left),
                label: const Text('上一页'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('${currentPage + 1}/$pageCount'),
            ),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: canGoNext ? onNext : null,
                icon: const Icon(Icons.chevron_right),
                label: const Text('下一页'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 空状态也放在可滚动列表中，让下拉刷新始终可用。
class _EmptyScrollableMessage extends StatelessWidget {
  const _EmptyScrollableMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [Center(child: Text(message))],
    );
  }
}
