import 'dart:math' as math;

import 'package:flutter/material.dart';

class ImageDetailsScreen extends StatelessWidget {
  const ImageDetailsScreen({
    super.key,
    required this.imageId,
    required this.imageUrl,
  });

  final String imageId;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Image Details')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight;

          final calculatedImageHeight = availableHeight * 0.65;

          final imageHeight = math.min(
            700.0,
            math.max(360.0, calculatedImageHeight),
          );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                width: double.infinity,
                height: imageHeight,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: Image.network(
                      imageUrl,
                      width: double.infinity,
                      height: imageHeight,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) {
                          return child;
                        }

                        final expectedBytes =
                            loadingProgress.expectedTotalBytes;

                        final value = expectedBytes == null
                            ? null
                            : loadingProgress.cumulativeBytesLoaded /
                                  expectedBytes;

                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(value: value),
                              const SizedBox(height: 16),
                              const Text('Loading full image...'),
                            ],
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.broken_image_outlined, size: 52),
                                SizedBox(height: 12),
                                Text(
                                  'Unable to load the full image.',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Associated Images',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.collections_outlined, size: 44),
                    SizedBox(height: 12),
                    Text(
                      'No associated images yet.',
                      style: TextStyle(fontSize: 17),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
