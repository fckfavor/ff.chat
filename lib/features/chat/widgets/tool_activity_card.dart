import 'package:flutter/material.dart';

import '../../../core/agent/permission_gate.dart';

/// Agent tool cagrisinin canli karti — Claude Code'in tool use satiri gibi.
class ToolActivity {
  ToolActivity({
    required this.id,
    required this.toolName,
    required this.argsPreview,
    this.status = 'running',
    this.output,
    this.elapsedMs,
  });

  final String id;
  final String toolName;
  String argsPreview;
  String status; // running | done | error | denied
  String? output;
  int? elapsedMs;
}

/// Chat icinde gomulu calisan tool karti.
class ToolActivityCard extends StatelessWidget {
  const ToolActivityCard({super.key, required this.activity});

  final ToolActivity activity;

  IconData get _icon {
    switch (activity.toolName) {
      case 'shell_exec':
        return Icons.terminal;
      case 'file_write':
      case 'file_edit':
        return Icons.edit_note;
      case 'file_delete':
        return Icons.delete_outline;
      case 'file_glob':
      case 'file_grep':
        return Icons.search;
      case 'todo_write':
        return Icons.checklist;
      case 'dispatch_subtask':
        return Icons.account_tree_outlined;
      default:
        return Icons.build_outlined;
    }
  }

  Color _statusColor(BuildContext context) {
    switch (activity.status) {
      case 'running':
        return Colors.blue;
      case 'error':
        return Colors.red;
      case 'denied':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  String get _statusLabel {
    switch (activity.status) {
      case 'running':
        return 'calisiyor...';
      case 'error':
        return 'hata';
      case 'denied':
        return 'reddedildi';
      default:
        return 'tamam';
    }
  }

  @override
  Widget build(BuildContext context) {
    final sc = _statusColor(context);
    final isDark = true;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: sc.withValues(alpha: 0.35)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: activity.status == 'running' || (activity.output?.length ?? 0) < 600,
          tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          leading: activity.status == 'running'
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: sc),
                )
              : Icon(_icon, size: 16, color: sc),
          title: Row(
            children: [
              Text(
                activity.toolName,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF4EC9B0), fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  activity.argsPreview.split('\n').first,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                Text(_statusLabel, style: TextStyle(fontSize: 10, color: sc)),
                if (activity.elapsedMs != null)
                  Text(' • ${activity.elapsedMs}ms', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
              ],
            ),
          ),
          children: [
            if (activity.argsPreview.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF111114), borderRadius: BorderRadius.circular(6)),
                  child: SelectableText(
                    activity.argsPreview,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFFD4D4D4), height: 1.35),
                  ),
                ),
              ),
            if (activity.output != null && activity.output!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 220),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF111114), borderRadius: BorderRadius.circular(6)),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      activity.output!,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.35,
                        color: activity.status == 'error' ? const Color(0xFFF48771) : const Color(0xFFC8C8C8),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Alt tarafta bekleyen izin istegi — Claude Code'un onay prompt'u gibi.
class PermissionPromptBar extends StatelessWidget {
  const PermissionPromptBar({
    super.key,
    required this.toolName,
    required this.preview,
    required this.onRespond,
  });

  final String toolName;
  final String preview;
  final void Function(PermissionResponse response) onRespond;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF242428),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gpp_maybe_outlined, size: 16, color: Colors.amber),
              const SizedBox(width: 6),
              Expanded(child: Text('$toolName icin izin?', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 160),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFF111114), borderRadius: BorderRadius.circular(6)),
            child: SingleChildScrollView(
              child: SelectableText(
                preview,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFFD4D4D4), height: 1.35),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => onRespond(PermissionResponse.deny()),
                  child: const Text('Reddet'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () => onRespond(PermissionResponse.allow(dontAskAgain: true)),
                  child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Oturumda hep izin ver')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => onRespond(PermissionResponse.allow()),
                  child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Onayla')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
