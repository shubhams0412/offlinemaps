import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class GuruSearchBar extends StatelessWidget {
  static const Color _surface = Color(0xFF141922);
  static const Color _border = Color(0xFF2B3647);
  static const Color _primary = Color(0xFF4C8DFF);

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onBack;
  final ValueChanged<String> onChanged;
  final bool isSearching;

  const GuruSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onBack,
    required this.onChanged,
    this.isSearching = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white54, size: 18),
                onPressed: onBack,
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Search places, addresses...',
                    hintStyle: GoogleFonts.inter(
                      color: const Color(0xFF5A6577),
                      fontSize: 16,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onChanged: onChanged,
                ),
              ),
              if (controller.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white54, size: 20),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
            ],
          ),
          if (isSearching)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(14)),
              child: LinearProgressIndicator(
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(_primary),
                minHeight: 2,
              ),
            ),
        ],
      ),
    );
  }
}
