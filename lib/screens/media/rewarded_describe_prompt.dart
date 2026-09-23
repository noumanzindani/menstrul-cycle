import 'package:flutter/material.dart';

/// The opt-in a rewarded ad requires: the user is told what they get and
/// chooses. Returns true when they agreed to watch.
///
/// A separate file from the gate's decision logic (`rewarded_describe_gate`)
/// because this half needs a `BuildContext` and that half must stay testable
/// without one.
///
/// The copy names the exchange plainly and does NOT dress the ad up as a
/// feature. One ad starts one conversation (`earnOneConversation`); it avoids
/// promising the conversation is unlimited after the ad -- the per-conversation
/// turn cap and the daily cap still apply, and a prompt that implies otherwise
/// would be the app's own words contradicting the counter in the chat.
Future<bool> showRewardedDescribePrompt(BuildContext context) async {
  final agreed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Watch an ad to start a conversation?'),
      content: const Text(
        'Answers come from Google, which costs us per message. Watch a '
        'short ad to start this conversation.\n\n'
        'Nothing you type or attach is ever part of the ad, and advertisers '
        'are never told anything about it.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Watch ad'),
        ),
      ],
    ),
  );
  return agreed ?? false;
}
