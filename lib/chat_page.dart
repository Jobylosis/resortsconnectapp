import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

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
  final String currentUid = FirebaseAuth.instance.currentUser!.uid;
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
    
    _encrypter = encrypt.Encrypter(encrypt.AES(key));
    final ivBytes = md5.convert(utf8.encode(chatId.split('').reversed.join())).bytes;
    _iv = encrypt.IV(Uint8List.fromList(ivBytes));
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
    });

    _updateChatRoom(currentUid, widget.otherUserUid, widget.otherUserName, encryptedMessage);
    _updateChatRoom(widget.otherUserUid, currentUid, "User", encryptedMessage);

    _messageController.clear();
  }

  void _updateChatRoom(String userUid, String otherUid, String otherName, String lastMsgEncrypted) async {
    String nameToStore = otherName;
    if (userUid == widget.otherUserUid) {
      final snapshot = await FirebaseDatabase.instance.ref("users/$currentUid").get();
      if (snapshot.exists) {
        Map data = snapshot.value as Map;
        nameToStore = "${data['firstName']} ${data['lastName']}";
      }
    }

    FirebaseDatabase.instance.ref("chat_rooms/$userUid/$otherUid").set({
      'otherUserName': nameToStore,
      'lastMessage': lastMsgEncrypted,
      'timestamp': ServerValue.timestamp,
    });
  }

  @override
  Widget build(BuildContext context) {
    final Query chatQuery = FirebaseDatabase.instance.ref("chats/$chatId/messages").orderByChild("timestamp");

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.otherUserName),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
      ),
      body: Column(
        children: [
          Expanded(
            child: FirebaseAnimatedList(
              query: chatQuery,
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, snapshot, animation, index) {
                Map msg = snapshot.value as Map;
                bool isMe = msg['senderUid'] == currentUid;
                
                String decryptedText = _decryptText(msg['text'] ?? '');

                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isMe ? const Color(0xFF2196F3) : Colors.grey[200],
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(15),
                        topRight: const Radius.circular(15),
                        bottomLeft: Radius.circular(isMe ? 15 : 0),
                        bottomRight: Radius.circular(isMe ? 0 : 15),
                      ),
                    ),
                    child: Text(
                      decryptedText,
                      style: TextStyle(color: isMe ? Colors.white : Colors.black87),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send, color: Color(0xFF2196F3)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
