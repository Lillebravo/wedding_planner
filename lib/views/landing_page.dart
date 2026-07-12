import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/wedding_model.dart';
import '../services/storage_service.dart';
import 'guest_list_page.dart';
import 'onboarding_page.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  Wedding? _wedding;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWeddingData();
  }

  void _loadWeddingData() async {
    Wedding? w = await StorageService.getActiveWedding();
    setState(() {
      _wedding = w;
      _isLoading = false;
    });
  }

  void _logout() async {
    await StorageService.clearActiveWedding();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const OnboardingPage()),
    );
  }

  Future<void> _uploadNewCover() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final selectedFile = result?.files.single;

    if (selectedFile == null || _wedding == null) {
      return;
    }

    if (!mounted) return;

    if (selectedFile.bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Kunde inte lasa den valda bilden. Testa en annan fil.',
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final uploadResult = await StorageService.uploadCoverImage(
      _wedding!.id,
      selectedFile.name,
      selectedFile.bytes!,
    );

    if (!mounted) return;

    if (!uploadResult.isSuccess) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uploadResult.errorMessage ?? 'Bilduppladdningen misslyckades.',
          ),
        ),
      );
      return;
    }

    try {
      final updatedWedding = Wedding(
        id: _wedding!.id,
        partner1: _wedding!.partner1,
        partner2: _wedding!.partner2,
        dateStr: _wedding!.dateStr,
        timeStr: _wedding!.timeStr,
        code: _wedding!.code,
        churchAddress: _wedding!.churchAddress,
        venueAddress: _wedding!.venueAddress,
        coverImageUrl: uploadResult.publicUrl,
        itinerary: _wedding!.itinerary,
      );

      final savedWedding = await StorageService.updateWedding(updatedWedding);
      await StorageService.saveActiveWedding(savedWedding);

      setState(() {
        _wedding = savedWedding;
        _isLoading = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Omslagsbilden uppdaterades.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bilden laddades upp men URL kunde inte sparas i weddings: $e',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_wedding == null) {
      return const OnboardingPage();
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 250.0,
            floating: false,
            pinned: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.people),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const GuestListPage(),
                  ),
                ),
              ),
              IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                '${_wedding!.partner1} & ${_wedding!.partner2}',
                style: const TextStyle(
                  color: Colors.white,
                  shadows: [Shadow(color: Colors.black, blurRadius: 10)],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  _wedding!.coverImageUrl != null
                      ? Image.network(
                          _wedding!.coverImageUrl!,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: Colors.pink[100],
                          child: const Icon(
                            Icons.favorite,
                            size: 80,
                            color: Colors.white,
                          ),
                        ),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: FloatingActionButton.small(
                      heroTag: 'upload_btn',
                      onPressed: _uploadNewCover,
                      child: const Icon(Icons.camera_alt),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Detaljer för dagen',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: ListTile(
                        leading: const Icon(
                          Icons.calendar_month,
                          color: Colors.pink,
                        ),
                        title: Text('Datum: ${_wedding!.dateStr}'),
                        subtitle: Text('Tid: ${_wedding!.timeStr}'),
                      ),
                    ),
                    if (_wedding!.churchAddress.isNotEmpty)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.church, color: Colors.blue),
                          title: const Text('Vigsel'),
                          subtitle: Text(_wedding!.churchAddress),
                        ),
                      ),
                    if (_wedding!.venueAddress.isNotEmpty)
                      Card(
                        child: ListTile(
                          leading: const Icon(
                            Icons.celebration,
                            color: Colors.orange,
                          ),
                          title: const Text('Festlokal'),
                          subtitle: Text(_wedding!.venueAddress),
                        ),
                      ),
                    const SizedBox(height: 24),
                    const Text(
                      'Tidslinje / Schema',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _wedding!.itinerary.isEmpty
                        ? const Text(
                            'Inget schema är satt ännu.',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _wedding!.itinerary.length,
                            itemBuilder: (context, index) {
                              final event = _wedding!.itinerary[index];
                              return ListTile(
                                leading: Text(
                                  event['time'] ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                title: Text(event['title'] ?? ''),
                              );
                            },
                          ),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
