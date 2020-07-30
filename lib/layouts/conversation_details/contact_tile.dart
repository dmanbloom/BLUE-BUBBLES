import 'dart:ui';

import 'package:bluebubble_messages/blocs/chat_bloc.dart';
import 'package:bluebubble_messages/helpers/utils.dart';
import 'package:bluebubble_messages/layouts/widgets/contact_avatar_widget.dart';
import 'package:bluebubble_messages/managers/contact_manager.dart';
import 'package:bluebubble_messages/repository/models/chat.dart';
import 'package:bluebubble_messages/repository/models/handle.dart';
import 'package:bluebubble_messages/socket_manager.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intent/intent.dart' as android_intent;
import 'package:intent/action.dart' as android_action;
import 'package:permission_handler/permission_handler.dart';

class ContactTile extends StatefulWidget {
  final Contact contact;
  final Handle handle;
  final Chat chat;
  final Function updateChat;
  final bool canBeRemoved;
  ContactTile({
    Key key,
    this.contact,
    this.handle,
    this.chat,
    this.updateChat,
    this.canBeRemoved,
  }) : super(key: key);

  @override
  _ContactTileState createState() => _ContactTileState();
}

class _ContactTileState extends State<ContactTile> {
  ImageProvider contactImage;

  @override
  Future<void> didChangeDependencies() async {
    super.didChangeDependencies();
    getAvatar(widget);
    ContactManager().stream.listen((event) {
      getAvatar(widget);
    });
  }

  Future<void> getAvatar(ContactTile widget) async {
    if (contactImage != null) return;

    if (widget.contact != null && widget.contact.avatar.length > 0) {
      contactImage = MemoryImage(widget.contact.avatar);
      if (this.mounted) setState(() {});
    }
  }

  Widget _buildContactTile() {
    var initials = getInitials(widget.contact?.displayName ?? "", " ");
    return InkWell(
      onLongPress: () {
        Clipboard.setData(new ClipboardData(text: widget.handle.address));
        final snackBar = SnackBar(content: Text("Address copied to clipboard"));
        Scaffold.of(context).showSnackBar(snackBar);
      },
      onTap: () async {
        if (widget.contact == null) {
          await ContactsService.openContactForm();
        } else {
          await ContactsService.openExistingContact(widget.contact);
        }
      },
      child: ListTile(
        title: Text(
          widget.contact != null
              ? widget.contact.displayName
              : widget.handle.address,
          style: Theme.of(context).textTheme.bodyText1,
        ),
        leading: ContactAvatarWidget(
          contactImage: contactImage,
          initials: initials,
        ),
        trailing: SizedBox(
          width: MediaQuery.of(context).size.width / 3,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              ButtonTheme(
                minWidth: 1,
                child: FlatButton(
                  shape: CircleBorder(),
                  color: Theme.of(context).accentColor,
                  onPressed: () async {
                    if (widget.contact != null &&
                        widget.contact.phones.length > 0) {
                      if (await Permission.phone.request().isGranted) {
                        android_intent.Intent()
                          ..setAction(android_action.Action.ACTION_CALL)
                          ..setData(Uri(
                              scheme: "tel",
                              path: widget.contact.phones.first.value))
                          ..startActivity().catchError((e) => print(e));
                      }
                    }
                  },
                  child: Icon(
                    Icons.call,
                    color: Colors.blue,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.canBeRemoved
        ? Slidable(
            actionExtentRatio: 0.25,
            actionPane: SlidableStrechActionPane(),
            secondaryActions: <Widget>[
              IconSlideAction(
                caption: 'Remove',
                color: Colors.red,
                icon: Icons.delete,
                onTap: () async {
                  showDialog(
                    context: context,
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: SizedBox(
                        height: 40,
                        width: 40,
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  );

                  Map<String, dynamic> params = new Map();
                  params["identifier"] = widget.chat.guid;
                  params["address"] = widget.handle.address;
                  SocketManager().sendMessage("remove-participant", params,
                      (response) async {
                    debugPrint("removed participant participant " +
                        response.toString());
                    if (response["status"] == 200) {
                      Chat updatedChat = Chat.fromMap(response["data"]);
                      await updatedChat.save();
                      ChatBloc().moveChatToTop(updatedChat);
                      Chat chatWithParticipants =
                          await updatedChat.getParticipants();
                      debugPrint(
                          "updating chat with ${chatWithParticipants.participants.length} participants");
                      widget.updateChat(chatWithParticipants);
                      Navigator.of(context).pop();
                    }
                  });
                },
              ),
            ],
            child: _buildContactTile(),
          )
        : _buildContactTile();
  }
}
