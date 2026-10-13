import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/shorts_controller.dart';
import '../widgets/shorts_player_widget.dart';

/// Full-screen vertical shorts feed (swipe up/down).
class ShortsScreen extends ConsumerStatefulWidget {
  const ShortsScreen({super.key});

  @override
  ConsumerState<ShortsScreen> createState() =>
      _ShortsScreenState();
}

class _ShortsScreenState
    extends ConsumerState<ShortsScreen> {
  static const _accent = Color(0xFF10B981);
  final _pageCtrl = PageController();

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state =
        ref.watch(shortsControllerProvider);
    final notifier =
        ref.read(shortsControllerProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: state.loading
            ? const Center(
                child: CircularProgressIndicator(
                    color: _accent))
            : state.error != null
                ? Center(
                    child: Column(
                      mainAxisSize:
                          MainAxisSize.min,
                      children: [
                        const Text(
                            'Could not load shorts',
                            style: TextStyle(
                                color: Colors.grey)),
                        const SizedBox(
                            height: 12),
                        ElevatedButton(
                          onPressed:
                              notifier.retry,
                          style: ElevatedButton
                              .styleFrom(
                                  backgroundColor:
                                      _accent,
                                  foregroundColor:
                                      Colors.black),
                          child: const Text(
                              'Retry',
                              style: TextStyle(
                                  color: Colors.black,
                                  fontWeight:
                                      FontWeight.bold)),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      PageView.builder(
                        controller: _pageCtrl,
                        scrollDirection:
                            Axis.vertical,
                        itemCount:
                            state.shorts.length,
                        onPageChanged:
                            notifier.setIndex,
                        itemBuilder: (_, i) {
                          // Pre-load neighbors: build active + adjacent.
                          final isActive =
                              i ==
                                  state
                                      .currentIndex;
                          final isNeighbor =
                              (i - state.currentIndex)
                                      .abs() <=
                                  1;
                          if (!isNeighbor) {
                            return Container(
                                color: Colors
                                    .black);
                          }
                          return ShortsPlayerWidget(
                            key: ValueKey(state
                                .shorts[i].id),
                            video:
                                state.shorts[i],
                            isActive: isActive,
                          );
                        },
                      ),
                      // Top bar.
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                                  horizontal: 8,
                                  vertical: 4),
                          decoration:
                              const BoxDecoration(
                            gradient:
                                LinearGradient(
                              begin: Alignment
                                  .topCenter,
                              end: Alignment
                                  .bottomCenter,
                              colors: [
                                Colors.black54,
                                Colors.transparent
                              ],
                            ),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(
                                    Icons
                                        .arrow_back,
                                    color: Colors
                                        .white),
                                onPressed: () =>
                                    Navigator.pop(
                                        context),
                              ),
                              const Text(
                                'Shorts',
                                style: TextStyle(
                                    color: Colors
                                        .white,
                                    fontSize:
                                        18,
                                    fontWeight:
                                        FontWeight
                                            .bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
