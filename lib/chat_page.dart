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
  bool _isBlocked = false;        // I blocked them
  bool _isBlockedByOther = false; // they blocked me
  String? _myRole;
  String? _otherRole;

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
    final ivBytes =
        md5.convert(utf8.encode(chatId.split('').reversed.join(''))).bytes;
    _iv = encrypt.IV(Uint8List.fromList(ivBytes));

    // Reset unread count when opening the chat
    FirebaseDatabase.instance
        .ref("chat_rooms/$currentUid/${widget.otherUserUid}")
        .update({'unreadCount': 0});

    // Listen to block status
    FirebaseDatabase.instance
        .ref("blocks/$currentUid/${widget.otherUserUid}")
        .onValue
        .listen((event) {
      if (mounted) setState(() => _isBlocked = event.snapshot.exists);
    });
    FirebaseDatabase.instance
        .ref("blocks/${widget.otherUserUid}/$currentUid")
        .onValue
        .listen((event) {
      if (mounted) setState(() => _isBlockedByOther = event.snapshot.exists);
    });

    FirebaseDatabase.instance.ref("users/$currentUid/role").onValue.listen((event) {
      if (mounted) setState(() => _myRole = event.snapshot.value?.toString());
    });
    FirebaseDatabase.instance.ref("users/${widget.otherUserUid}/role").onValue.listen((event) {
      if (mounted) setState(() => _otherRole = event.snapshot.value?.toString());
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

  String _formatMessageTime(DateTime date) {
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    final isThisYear = date.year == now.year;

    if (isToday) {
      return DateFormat('hh:mm a').format(date);
    } else if (isThisYear) {
      return DateFormat('MMM d, hh:mm a').format(date);
    } else {
      return DateFormat('MMM d, yyyy, hh:mm a').format(date);
    }
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;
    if (_isBlocked || _isBlockedByOther) return;

    final DatabaseReference chatRef =
        FirebaseDatabase.instance.ref("chats/$chatId/messages").push();
    final String messageText = _messageController.text.trim();

    final String encryptedMessage = _encryptText(messageText);

    chatRef.set({
      'senderUid': currentUid,
      'text': encryptedMessage,
      'timestamp': ServerValue.timestamp,
      'seen': false,
    });

    _updateChatRoom(currentUid, widget.otherUserUid, widget.otherUserName,
        encryptedMessage, false);
    _updateChatRoom(
        widget.otherUserUid, currentUid, "User", encryptedMessage, true);

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

  void _showReportDialog(BuildContext context) {
    final TextEditingController reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: AppTheme.primaryAccent.withOpacity(0.1),
                    shape: BoxShape.circle),
                child: Icon(Icons.report_problem_rounded,
                    color: AppTheme.primaryAccent, size: 32),
              ),
              const SizedBox(height: 16),
              const Text("Report User",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text("Please describe the issue with this user. This report will be sent to the super admin for review.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                maxLines: 3,
                style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
                decoration: InputDecoration(
                  hintText: "Reason for reporting...",
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: Colors.grey.withOpacity(0.1),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Cancel",
                          style: TextStyle(
                              color: Colors.grey, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryAccent,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        if (reasonController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Must input a reason for reporting user.'),
                                backgroundColor: Colors.red),
                          );
                          return;
                        }
                        try {
                          await FirebaseDatabase.instance
                              .ref("reports")
                              .push()
                              .set({
                            'reportedUid': widget.otherUserUid,
                            'reportedName': widget.otherUserName,
                            'reporterUid': currentUid,
                            'reason': reasonController.text.trim(),
                            'status': 'pending',
                            'timestamp': ServerValue.timestamp,
                          });
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Report submitted to super admin.'),
                                  backgroundColor: Colors.green),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Failed to submit report. Please try again or check connection. Error: $e'),
                                  backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                      child: const Text("Submit",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  void _showBlockDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    shape: BoxShape.circle),
                child: const Icon(Icons.block_rounded,
                    color: Colors.orange, size: 32),
              ),
              const SizedBox(height: 16),
              const Text("Block User?",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                  "Are you sure you want to block this user? You will no longer receive messages from this user. This action can be undone later.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Cancel",
                          style: TextStyle(
                              color: Colors.grey, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        Navigator.pop(context); // close dialog
                        try {
                          await FirebaseDatabase.instance
                              .ref("blocks/$currentUid/${widget.otherUserUid}")
                              .set({
                            'blockedAt': ServerValue.timestamp,
                            'blockedName': widget.otherUserName,
                          });
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      '${widget.otherUserName} has been blocked.'),
                                  backgroundColor: Colors.orange),
                            );
                            Navigator.pop(context); // go back from chat
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Failed to block user: $e'),
                                  backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                      child: const Text("Block",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  void _showClearDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: AppTheme.primaryAccent.withOpacity(0.1),
                    shape: BoxShape.circle),
                child: Icon(Icons.delete_sweep_rounded,
                    color: AppTheme.primaryAccent, size: 32),
              ),
              const SizedBox(height: 16),
              const Text("Clear Chat?",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                  "Are you sure to clear the chat history? This will permanently delete all messages in this conversation for you. This action cannot be undone.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Cancel",
                          style: TextStyle(
                              color: Colors.grey, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryAccent,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        await FirebaseDatabase.instance
                            .ref("chats/$chatId/messages")
                            .remove();
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Chat history cleared.'),
                                backgroundColor: Colors.green),
                          );
                        }
                      },
                      child: const Text("Clear",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  void _showUnblockDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    shape: BoxShape.circle),
                child: const Icon(Icons.lock_open_rounded,
                    color: Colors.green, size: 32),
              ),
              const SizedBox(height: 16),
              const Text("Unblock User?",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                  "Are you sure you want to unblock ${widget.otherUserName}? You will be able to send and receive messages again.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Cancel",
                          style: TextStyle(
                              color: Colors.grey, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        Navigator.pop(context);
                        try {
                          await FirebaseDatabase.instance
                              .ref("blocks/$currentUid/${widget.otherUserUid}")
                              .remove();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      '${widget.otherUserName} has been unblocked.'),
                                  backgroundColor: Colors.green),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Failed to unblock: $e'),
                                  backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                      child: const Text("Unblock",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  List<String> _parseList(dynamic data) {
    if (data == null) return [];
    if (data is List)
      return data.where((e) => e != null).map((e) => e.toString()).toList();
    if (data is Map) {
      var sortedKeys = data.keys.toList()
        ..sort((a, b) => a.toString().compareTo(b.toString()));
      return sortedKeys.map((k) => data[k].toString()).toList();
    }
    return [];
  }

  void _updateChatRoom(String userUid, String otherUid, String otherName,
      String lastMsgEncrypted, bool incrementUnread) async {
    String nameToStore = otherName;
    String? otherPhoto;

    try {
      if (userUid == widget.otherUserUid) {
        // We are updating the RECIPIENT'S chat room metadata
        // The 'other' user for them is ME (the current sender)
        final snapshot =
            await FirebaseDatabase.instance.ref("users/$currentUid").get();
        if (snapshot.exists) {
          Map data = snapshot.value as Map;
          nameToStore =
              "${data['firstName'] ?? ''} ${data['lastName'] ?? ''}".trim();
          if (nameToStore.isEmpty) nameToStore = "User";
          otherPhoto = data['profilePicUrl'];
        }

        // If it's still empty or generic, check if I'm an owner
        if (nameToStore == "User" || nameToStore.isEmpty) {
          final propSnap = await FirebaseDatabase.instance
              .ref("properties/$currentUid")
              .get();
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
        final snapshot =
            await FirebaseDatabase.instance.ref("users/$otherUid").get();
        if (snapshot.exists) {
          Map data = snapshot.value as Map;
          otherPhoto = data['profilePicUrl'];
        } else {
          // Check properties if owner
          final propSnap =
              await FirebaseDatabase.instance.ref("properties/$otherUid").get();
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

    final roomRef =
        FirebaseDatabase.instance.ref("chat_rooms/$userUid/$otherUid");

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
    final Query chatQuery = FirebaseDatabase.instance
        .ref("chats/$chatId/messages")
        .orderByChild("timestamp")
        .limitToLast(_msgLimit);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: secondaryColor.withOpacity(0.1),
              child: Text(widget.otherUserName[0].toUpperCase(),
                  style: TextStyle(
                      color: secondaryColor,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Text(widget.otherUserName,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold))),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded, size: 20),
            onPressed: _loadMoreMessages,
            tooltip: 'Load older messages',
          ),
          IconButton(
            icon: Icon(themeProvider.themeMode == ThemeMode.dark
                ? Icons.light_mode_rounded
                : Icons.dark_mode_rounded),
            onPressed: () => themeProvider.toggleTheme(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              if (value == 'report') {
                _showReportDialog(context);
              } else if (value == 'block') {
                _showBlockDialog(context);
              } else if (value == 'unblock') {
                _showUnblockDialog(context);
              } else if (value == 'clear') {
                _showClearDialog(context);
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              if (!(_myRole == 'Tourist' && _otherRole == 'Owner'))
                const PopupMenuItem<String>(
                  value: 'report',
                  child: Text('Report User'),
                ),
              if (_myRole != 'Tourist')
                PopupMenuItem<String>(
                  value: _isBlocked ? 'unblock' : 'block',
                  child: Text(_isBlocked ? 'Unblock User' : 'Block User',
                      style: TextStyle(
                          color: _isBlocked ? Colors.green : Colors.red)),
                ),
              if (_myRole != 'Tourist')
                const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'clear',
                child: Text('Clear Chat',
                    style: TextStyle(color: AppTheme.primaryAccent)),
              ),
            ],
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
                  date = DateTime.fromMillisecondsSinceEpoch(
                      msg['timestamp'] is int ? msg['timestamp'] : 0);
                }

                if (!isMe && msg['seen'] == false) {
                  FirebaseDatabase.instance
                      .ref("chats/$chatId/messages/${snapshot.key}")
                      .update({'seen': true});
                }

                return Align(
                  alignment:
                      isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: isMe
                              ? secondaryColor
                              : Theme.of(context).colorScheme.surface,
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
                            color: isMe
                                ? Colors.white
                                : Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (date != null)
                        Padding(
                          padding: const EdgeInsets.only(
                              bottom: 8, left: 4, right: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatMessageTime(date),
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[500],
                                    fontWeight: FontWeight.w600),
                              ),
                              if (isMe) ...[
                                const SizedBox(width: 4),
                                Icon(Icons.done_all_rounded,
                                    size: 14,
                                    color: msg['seen'] == true
                                        ? Colors.blue
                                        : Colors.grey[400]),
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
          // Block status banners
          if (_isBlocked)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.orange.withValues(alpha: 0.12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '🚫 You have blocked ${widget.otherUserName}.',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.brown),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _showUnblockDialog(context),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.orange,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(color: Colors.orange)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                    ),
                    child: const Text('Unblock',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          if (_isBlockedByOther && !_isBlocked)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.red.withValues(alpha: 0.1),
              child: const Text(
                '⛔ You cannot send messages to this user.',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.red),
              ),
            ),
          Container(
            padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).padding.bottom + 16),
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
                    enabled: !_isBlocked && !_isBlockedByOther,
                    decoration: InputDecoration(
                      hintText: (_isBlocked || _isBlockedByOther)
                          ? 'Messaging is unavailable.'
                          : 'Type a message...',
                      fillColor: themeProvider.themeMode == ThemeMode.dark
                          ? AppTheme.darkBg.withOpacity(0.5)
                          : Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    color: (_isBlocked || _isBlockedByOther)
                        ? Colors.grey[300]
                        : secondaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: (_isBlocked || _isBlockedByOther)
                        ? null
                        : _sendMessage,
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
