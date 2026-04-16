import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PlaceInfoPanel extends StatelessWidget {
  static const Color _surfaceColor = Color(0xFF141922);
  static const Color _borderColor = Color(0xFF2B3647);
  static const Color _primaryColor = Color(0xFF4C8DFF);
  static const Color _mutedTextColor = Color(0xFF95A1B3);

  final String title;
  final String subtitle;
  final String? address;
  final String? phone;
  final String? website;
  final String? latLng;
  final VoidCallback onClose;
  final VoidCallback onNavigate;

  const PlaceInfoPanel({
    super.key,
    required this.title,
    required this.subtitle,
    this.address,
    this.phone,
    this.website,
    this.latLng,
    required this.onClose,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: const Border(top: BorderSide(color: _borderColor, width: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Padding(
            padding: EdgeInsets.fromLTRB(
              20, 14, 20,
              MediaQuery.of(context).padding.bottom + 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: GoogleFonts.inter(
                              color: _primaryColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: onClose,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFF202938),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white38,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                if (address != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    address!,
                    style: GoogleFonts.inter(
                      color: _mutedTextColor,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Container(height: 0.5, color: _borderColor),
                const SizedBox(height: 12),

                // Info rows
                _buildInfoRow(
                  Icons.my_location_rounded,
                  latLng ?? '+23.0585, +72.5174',
                ),
                if (phone != null)
                  _buildInfoRow(Icons.phone_outlined, phone!),
                if (website != null)
                  _buildInfoRow(Icons.language_rounded, website!),

                const SizedBox(height: 20),

                // Navigation button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: onNavigate,
                    icon: const Icon(
                      Icons.navigation_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    label: Text(
                      'Directions',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _mutedTextColor),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                color: _primaryColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
