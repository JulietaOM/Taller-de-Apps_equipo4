import 'package:flutter/material.dart';
import 'ecg_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color _primary = Color(0xFFF78B94);
  static const Color _soft    = Color(0xFFF8ABBB);
  static const Color _pale    = Color(0xFFFADEDF);
  static const Color _white   = Colors.white;

  final _nameController = TextEditingController();
  String _sex = 'No especificado';
  final _ageController = TextEditingController();

  static const _sexOptions = ['No especificado', 'Femenino', 'Masculino', 'Otro'];

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  void _goToEcg() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EcgScreen(
          name: _nameController.text.trim(),
          sex: _sex,
          age: _ageController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _white,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: _primary,
        elevation: 2,
        centerTitle: true,
        title: const Text(
          'Heartbeat',
          style: TextStyle(
            fontFamily: 'serif',
            color: _white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── Imagen de perfil ────────────────────────────────────
            Container(
              width: double.infinity,
              height: 260,
              color: Colors.grey.shade100,
              child: Center(
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _soft, width: 3),
                    image: const DecorationImage(
                      image: AssetImage('assets/logo.png'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),

            // ── Nombre ─────────────────────────────────────────────
            _InfoRow(
              label: 'Nombre:',
              color: _pale,
              child: TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: 'Tu nombre',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                style: const TextStyle(
                  fontFamily: 'serif',
                  fontSize: 16,
                  color: Color(0xFF444444),
                ),
              ),
            ),

            // ── Sexo ───────────────────────────────────────────────
            _InfoRow(
              label: 'Sexo:',
              color: _soft,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _sex,
                  isDense: true,
                  style: const TextStyle(
                    fontFamily: 'serif',
                    fontSize: 16,
                    color: Color(0xFF444444),
                  ),
                  items: _sexOptions
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setState(() => _sex = v ?? _sex),
                ),
              ),
            ),

            // ── Edad ───────────────────────────────────────────────
            _InfoRow(
              label: 'Edad:',
              color: _pale,
              child: TextField(
                controller: _ageController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Tu edad',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                style: const TextStyle(
                  fontFamily: 'serif',
                  fontSize: 16,
                  color: Color(0xFF444444),
                ),
              ),
            ),

            // ── Botón Iniciar ───────────────────────────────────────
            Container(
              width: double.infinity,
              height: 160,
              color: _white,
              alignment: Alignment.center,
              child: ElevatedButton(
                onPressed: _goToEcg,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: _white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'serif',
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                  elevation: 0,
                ),
                child: const Text('Iniciar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Widget auxiliar ───────────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.color,
    required this.child,
  });

  final String label;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 60,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'serif',
                fontSize: 16,
                color: Color(0xFF555555),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}