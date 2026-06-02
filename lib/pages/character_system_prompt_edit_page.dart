import 'package:flutter/material.dart';

class CharacterSystemPromptEditPage extends StatefulWidget {
  final String initialText;
  const CharacterSystemPromptEditPage({super.key, required this.initialText});

  @override
  State<CharacterSystemPromptEditPage> createState() =>
      _CharacterSystemPromptEditPageState();
}

class _CharacterSystemPromptEditPageState
    extends State<CharacterSystemPromptEditPage> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _saveAndPop() {
    Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop) {
          _saveAndPop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _saveAndPop,
          ),
          title: const Text('角色详细设定'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _controller,
            autofocus: true,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              hintText: '输入角色的详细设定，例如：\n你是一个温柔的助手，说话轻声细语...',
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ),
    );
  }
}