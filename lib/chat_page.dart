import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'theme_provider.dart';
import 'theme.dart';

class ChatPage extends StatefulWidget {
  final String otherUserUid;
  final String otherUserName;

  const ChatPage({
    super.key,
    required this.otherUserUid,
    required this.otherUserName,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final String currentUid = FirebaseAuth.instance.currentUser!.uid;
  int _msgLimit = 20;
  final bool _canLoadMore = true;
  late String chatId;
  
  late encrypt.Encrypter _encrypter;
  late encrypt.IV _iv;

  @override
  void initState() {
    super.initState();
    List<String> ids = [currentUid, widget.otherUserUid];
    ids.sort();
    chatId = ids.join("_");

    final keyBytes = sha256.convert(utf8.encode(chatId)).bytes;
    final key = encrypt.Key(Uint8List.fromList(keyBytes));
    
    // Explicitly use CBC mode to match the website's CryptoJS implementation
    _encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    final ivBytes = md5.convert(utf8.encode(chatId.split('').reversed.join(''))).bytes;
    _iv = encrypt.IV(Uint8List.fromList(ivBytes));

    // Reset unread count when opening the chat
    FirebaseDatabase.instance.ref("chat_rooms/$currentUid/${widget.otherUserUid}").update({
      'unreadCount': 0
    });
  }

  String _encryptText(String text) {
    return _encrypter.encrypt(text, iv: _iv).base64;
  }

  String _decryptText(String encryptedBase64) {
    try {
      return _encrypter.decrypt64(encryptedBase64, iv: _iv);
    } catch (e) {
      return "[Encrypted Message]";
    }
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;

    final DatabaseReference chatRef = FirebaseDatabase.instance.ref("chats/$chatId/messages").push();
    final String messageText = _messageController.text.trim();

    final String encryptedMessage = _encryptText(messageText);

    chatRef.set({
      'senderUid': currentUid,
      'text': encryptedMessage,
      'timestamp': ServerValue.timestamp,
      'seen': false,
    });

    _updateChatRoom(currentUid, widget.otherUserUid, widget.otherUserName, encryptedMessage, false);
    _updateChatRoom(widget.otherUserUid, currentUid, "User", encryptedMessage, true);

    _messageController.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _loadMoreMessages() {
    setState(() {
      _msgLimit += 20;
    });
  }

  List<String> _parseList(dynamic data) {
    if (data == null) return [];
    if (data is List) return data.where((e) => e != null).map((e) => e.toString()).toList();
    if (data is Map) {
      var sortedKeys = data.keys.toList()..sort((a, b) => a.toString().compareTo(b.toString()));
      return sortedKeys.map((k) => data[k].toString()).toList();
    }
    return [];
  }

  void _updateChatRoom(String userUid, String otherUid, String otherName, String lastMsgEncrypted, bool incrementUnread) async {
    String nameToStore = otherName;
    String? otherPhoto;

    try {
      if (userUid == widget.otherUserUid) {
        // We are updating the RECIPIENT'S chat room metadata
        // The 'other' user for them is ME (the current sender)
        final snapshot = await FirebaseDatabase.instance.ref("users/$currentUid").get();
        if (snapshot.exists) {
          Map data = snapshot.value as Map;
          nameToStore = "${data['firstName'] ?? ''} ${data['lastName'] ?? ''}".trim();
          if (nameToStore.isEmpty) nameToStore = "User";
          otherPhoto = data['profilePicUrl'];
        }
        
        // If it's still empty or generic, check if I'm an owner
        if (nameToStore == "User" || nameToStore.isEmpty) {
          final propSnap = await FirebaseDatabase.instance.ref("properties/$currentUid").get();
          if (propSnap.exists) {
            Map propData = propSnap.value as Map;
            nameToStore = propData['name'] ?? nameToStore;
            List imgs = _parseList(propData['imageUrls']);
            if (imgs.isNotEmpty) otherPhoto = imgs[0];
          }
        }
      } else {
        // We are updating the SENDER'S own chat room metadata
        // The 'other' user for them is already known (widget.otherUserName)
        final snapshot = await FirebaseDatabase.instance.ref("users/$otherUid").get();
        if (snapshot.exists) {
          Map data = snapshot.value as Map;
          otherPhoto = data['profilePicUrl'];
        } else {
          // Check properties if owner
          final propSnap = await FirebaseDatabase.instance.ref("properties/$otherUid").get();
          if (propSnap.exists) {
            Map propData = propSnap.value as Map;
            List imgs = _parseList(propData['imageUrls']);
            if (imgs.isNotEmpty) otherPhoto = imgs[0];
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching profile for chat update: $e");
    }

    final roomRef = FirebaseDatabase.instance.ref("chat_rooms/$userUid/$otherUid");
    
    Map<String, dynamic> updates = {
      'otherUserName': nameToStore,
      'lastMessage': lastMsgEncrypted,
      'timestamp': ServerValue.timestamp,
    };
    if (otherPhoto != null) updates['otherProfilePic'] = otherPhoto;

    if (incrementUnread) {
      updates['unreadCount'] = ServerValue.increment(1);
    }

    await roomRef.update(updates).catchError((e) {
      debugPrint("Error updating chat room: $e");
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final secondaryColor = Theme.of(context).colorScheme.secondary;
    final Query chatQuery = FirebaseDatabase.instance.ref("chats/$chatId/messages").orderByChild("timestamp").limitToLast(_msgLimit);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: secondaryColor.withOpacity(0.1),
              child: Text(widget.otherUserName[0].toUpperCase(), style: TextStyle(color: secondaryColor, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(widget.otherUserName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded, size: 20),
            onPressed: _loadMoreMessages,
            tooltip: 'Load older messages',
          ),
          IconButton(
            icon: Icon(themeProvider.themeMode == ThemeMode.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
            onPressed: () => themeProvider.toggleTheme(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FirebaseAnimatedList(
              query: chatQuery,
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, snapshot, animation, index) {
                Map msg = snapshot.value as Map;
                bool isMe = msg['senderUid'] == currentUid;
                
                String decryptedText = _decryptText(msg['text'] ?? '');
                
                DateTime? date;
                if (msg['timestamp'] != null) {
                  date = DateTime.fromMillisecondsSinceEpoch(msg['timestamp'] is int ? msg['timestamp'] : 0);
                }

                if (!isMe && msg['seen'] == false) {
                  FirebaseDatabase.instance.ref("chats/$chatId/messages/${snapshot.key}").update({'seen': true});
                }

                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: isMe ? secondaryColor : Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20),
                            topRight: const Radius.circular(20),
                            bottomLeft: Radius.circular(isMe ? 20 : 4),
                            bottomRight: Radius.circular(isMe ? 4 : 20),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            )
                          ],
                        ),
                        child: Text(
                          decryptedText,
                          style: TextStyle(
                            color: isMe ? Colors.white : Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (date != null) Padding(
                        padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              DateFormat('hh:mm a').format(date),
                              style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.w600),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.done_all_rounded, 
                                size: 14, 
                                color: msg['seen'] == true ? Colors.blue : Colors.grey[400]
                              ),
                            ]
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            padding: EdgeInsets.only(
              left: 16, 
              right: 16, 
              top: 16, 
              bottom: MediaQuery.of(context).padding.bottom + 16
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                )
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      fillColor: themeProvider.themeMode == ThemeMode.dark 
                          ? AppTheme.darkBg.withOpacity(0.5) 
                          : Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    color: secondaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: _sendMessage,
                    icon: const Icon(Icons.send_rounded, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
