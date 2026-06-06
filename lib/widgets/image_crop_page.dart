import 'dart:typed_data';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

class ImageCropPage extends StatefulWidget {
  final Uint8List imageBytes;
  final double aspectRatio;
  final String title;
  final String guideText;

  const ImageCropPage({
    super.key,
    required this.imageBytes,
    required this.aspectRatio,
    required this.title,
    required this.guideText,
  });

  @override
  State<ImageCropPage> createState() => _ImageCropPageState();
}

class _ImageCropPageState extends State<ImageCropPage> {
  final CropController _controller = CropController();

  bool _cropping = false;
  bool _undoEnabled = false;
  bool _redoEnabled = false;

  void _crop() {
    if (_cropping) return;
    setState(() => _cropping = true);
    _controller.crop();
  }

  Widget _buildCropWidget() {
    final isPortraitCard = widget.aspectRatio < 0.8;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        color: Colors.black,
        child: Crop(
          image: widget.imageBytes,
          controller: _controller,
          aspectRatio: widget.aspectRatio,
          interactive: true,
          fixCropRect: true,
          baseColor: Colors.black,
          maskColor: Colors.black.withValues(
            alpha: isPortraitCard ? 0.68 : 0.58,
          ),
          radius: 12,
          initialRectBuilder: InitialRectBuilder.withSizeAndRatio(
            size: isPortraitCard ? 1.0 : 0.96,
            aspectRatio: widget.aspectRatio,
          ),
          cornerDotBuilder: (size, edgeAlignment) {
            return const SizedBox.shrink();
          },
          onHistoryChanged: (history) {
            setState(() {
              _undoEnabled = history.undoCount > 0;
              _redoEnabled = history.redoCount > 0;
            });
          },
          onCropped: (result) {
            switch (result) {
              case CropSuccess(:final croppedImage):
                Navigator.pop(context, croppedImage);

              case CropFailure(:final cause):
                setState(() => _cropping = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('裁剪失败：$cause')),
                );
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final isPortraitCard = widget.aspectRatio < 0.8;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // 主裁剪区域
              Expanded(
                child: Center(
                  child: isPortraitCard
                      ? FractionallySizedBox(
                    heightFactor: 0.92,
                    child: AspectRatio(
                      aspectRatio: widget.aspectRatio,
                      child: _buildCropWidget(),
                    ),
                  )
                      : Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                    child: SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                      child: _buildCropWidget(),
                    ),
                  ),
                ),
              ),

              // 底部操作面板
              SafeArea(
                top: false,
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    isPortraitCard ? 8 : 12,
                    16,
                    isPortraitCard ? 10 : 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.88),
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.guideText,
                        textAlign: TextAlign.center,
                        maxLines: isPortraitCard ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.68),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                      SizedBox(height: isPortraitCard ? 10 : 14),

                      Row(
                        children: [
                          IconButton(
                            tooltip: '撤销',
                            onPressed: _undoEnabled && !_cropping
                                ? _controller.undo
                                : null,
                            icon: const Icon(Icons.undo),
                            color: Colors.white,
                            disabledColor: Colors.white24,
                          ),
                          IconButton(
                            tooltip: '重做',
                            onPressed: _redoEnabled && !_cropping
                                ? _controller.redo
                                : null,
                            icon: const Icon(Icons.redo),
                            color: Colors.white,
                            disabledColor: Colors.white24,
                          ),

                          const Spacer(),

                          OutlinedButton(
                            onPressed: _cropping
                                ? null
                                : () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.58),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            child: const Text('取消'),
                          ),

                          const SizedBox(width: 12),

                          FilledButton(
                            onPressed: _cropping ? null : _crop,
                            style: FilledButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 26,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            child: const Text('确认裁剪'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          if (_cropping)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}