
class FoodMenuTab extends StatefulWidget {
  final Stream<DatabaseEvent> propStream;
  const FoodMenuTab({super.key, required this.propStream});

  @override
  State<FoodMenuTab> createState() => _FoodMenuTabState();
}

class _FoodMenuTabState extends State<FoodMenuTab> with AutomaticKeepAliveClientMixin {
  bool _isUploading = false;

  @override
  bool get wantKeepAlive => true;

  Future<void> _uploadMenuImages(List<String> currentUrls) async {
    final picker = ImagePicker();
    final List<XFile> images = await picker.pickMultiImage();
    if (images.isEmpty) return;

    setState(() => _isUploading = true);
    List<String> newUrls = List.from(currentUrls);

    for (var image in images) {
      try {
        final request = http.MultipartRequest('POST', Uri.parse('https://api.cloudinary.com/v1_1/dnv6ezitm/image/upload'))
          ..fields['upload_preset'] = 'resort_unsigned'
          ..files.add(await http.MultipartFile.fromPath('file', image.path));

        final response = await request.send();
        if (response.statusCode == 200) {
          final resData = await response.stream.bytesToString();
          final data = json.decode(resData);
          newUrls.add(data['secure_url']);
        }
      } catch (e) {
        debugPrint("Error uploading image: \$e");
      }
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseDatabase.instance.ref('properties/\$uid').update({
        'foodMenuUrls': newUrls,
      });
    }
    setState(() => _isUploading = false);
  }

  Future<void> _deleteMenuImage(List<String> currentUrls, int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Menu Image?'),
        content: const Text('Are you sure you want to remove this menu image?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      List<String> newUrls = List.from(currentUrls);
      newUrls.removeAt(index);
      
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseDatabase.instance.ref('properties/\$uid').update({
          'foodMenuUrls': newUrls,
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<DatabaseEvent>(
      stream: widget.propStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (!snapshot.data!.snapshot.exists) return const Center(child: Text("No property found."));

        final propData = snapshot.data!.snapshot.value as Map;
        final List<String> foodMenuUrls = [];
        if (propData['foodMenuUrls'] is List) {
          foodMenuUrls.addAll(List<String>.from(propData['foodMenuUrls']));
        }

        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Food Menu Management', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Upload your property\'s food menu images (Breakfast, Lunch, Dinner). Guests can view these images directly.', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 20),
              
              ElevatedButton.icon(
                onPressed: _isUploading ? null : () => _uploadMenuImages(foodMenuUrls),
                icon: _isUploading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.upload),
                label: Text(_isUploading ? 'Uploading...' : 'Upload Menu Images'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
              
              const SizedBox(height: 24),
              if (foodMenuUrls.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text('No menu images uploaded yet.', style: TextStyle(color: Colors.grey)),
                  ),
                )
              else
                Expanded(
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: foodMenuUrls.length,
                    itemBuilder: (context, index) {
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              foodMenuUrls[index],
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: () => _deleteMenuImage(foodMenuUrls, index),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close, color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
