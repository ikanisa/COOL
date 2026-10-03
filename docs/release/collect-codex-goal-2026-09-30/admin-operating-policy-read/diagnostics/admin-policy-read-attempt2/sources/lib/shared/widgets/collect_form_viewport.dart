import 'package:flutter/material.dart';

/// A finite-height form with one scroll owner for its header, body and actions.
///
/// The parent (normally a resizing Scaffold and SafeArea) supplies the usable
/// height. Do not put a scrolling widget in [body] or [actions]. The actions
/// must support intrinsic height measurement, as ordinary buttons do.
/// Short content leaves the actions at the viewport bottom; longer content or
/// a keyboard makes them reachable by scrolling, without a fixed height floor.
/// Styling, copy and validation remain the caller's responsibility.
class CollectFormViewport extends StatelessWidget {
  const CollectFormViewport({
    required this.header,
    required this.body,
    required this.actions,
    this.bodyPadding = EdgeInsets.zero,
    this.controller,
    this.maxWidth = double.infinity,
    super.key,
  }) : assert(maxWidth > 0);

  final Widget header;
  final Widget body;
  final Widget actions;
  final EdgeInsetsGeometry bodyPadding;
  final ScrollController? controller;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: CustomScrollView(
          controller: controller,
          primary: false,
          // Rebuilds and scrolling must not dismiss the keyboard while editing.
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
          slivers: [
            SliverToBoxAdapter(child: header),
            SliverPadding(
              padding: bodyPadding,
              sliver: SliverToBoxAdapter(child: body),
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Align(alignment: Alignment.bottomCenter, child: actions),
            ),
          ],
        ),
      ),
    );
  }
}
