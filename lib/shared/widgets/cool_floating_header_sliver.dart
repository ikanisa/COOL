import 'package:flutter/material.dart';

import 'cool_glass_header_surface.dart';

class CoolFloatingHeaderSliver extends StatelessWidget {
  const CoolFloatingHeaderSliver({
    this.leading,
    this.title,
    this.actions,
    this.automaticallyImplyLeading = false,
    super.key,
  });

  final Widget? leading;
  final Widget? title;
  final List<Widget>? actions;
  final bool automaticallyImplyLeading;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      automaticallyImplyLeading: automaticallyImplyLeading,
      backgroundColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: 68,
      floating: true,
      snap: true,
      flexibleSpace: const CoolGlassHeaderSurface(),
      leading: leading,
      title: title,
      actions: actions,
    );
  }
}
