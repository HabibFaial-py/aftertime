import { useState } from 'react';
import { Text, TextInput } from 'react-native';
import { router } from 'expo-router';
import { Action, Screen, styles } from '../components/ui';
import { validateDirectDraft } from '../lib/direct-draft';

export default function SendToSomeoneScreen() {
  const [recipient, setRecipient] = useState('');
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [date, setDate] = useState('');
  const [time, setTime] = useState('');
  const [feedback, setFeedback] = useState('');
  const [valid, setValid] = useState(false);
  const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone || 'device local time';

  function checkDetails() {
    const error = validateDirectDraft({ recipient, title, body, date, time });
    setValid(!error);
    setFeedback(error || 'Sending is not available yet. Nothing has been sent.');
  }
  function clearFeedback() { setFeedback(''); setValid(false); }

  return <Screen>
    <Text accessibilityRole="header" style={styles.title}>Send to Someone</Text>
    <Text style={styles.text}>Sending capsules to someone is not available yet. You can check your details here.</Text>
    <Text style={styles.label}>Recipient email</Text>
    <TextInput accessibilityLabel="Recipient email" style={styles.input} value={recipient}
      onChangeText={(value) => { setRecipient(value); clearFeedback(); }} keyboardType="email-address"
      autoCapitalize="none" autoCorrect={false} autoComplete="off" />
    <Text style={styles.label}>Title</Text>
    <TextInput accessibilityLabel="Title" style={styles.input} value={title}
      onChangeText={(value) => { setTitle(value); clearFeedback(); }} />
    <Text style={styles.label}>Private message</Text>
    <TextInput accessibilityLabel="Private message" style={styles.input} value={body}
      onChangeText={(value) => { setBody(value); clearFeedback(); }} multiline autoCorrect={false} autoComplete="off" />
    <Text style={styles.text}>{Array.from(body).length} / 2,000 characters</Text>
    <Text style={styles.label}>Local reveal date (YYYY-MM-DD)</Text>
    <TextInput accessibilityLabel="Local reveal date, year month day" style={styles.input} value={date}
      onChangeText={(value) => { setDate(value); clearFeedback(); }} placeholder="YYYY-MM-DD" placeholderTextColor="#6A5C52" />
    <Text style={styles.label}>Local reveal time, 24-hour (HH:MM)</Text>
    <TextInput accessibilityLabel="Local reveal time, 24-hour hours and minutes" style={styles.input} value={time}
      onChangeText={(value) => { setTime(value); clearFeedback(); }} placeholder="HH:MM" placeholderTextColor="#6A5C52" />
    <Text style={styles.text}>Timezone: {timezone}. Enter the local date and time on your device.</Text>
    <Action title="Check details" onPress={checkDetails} />
    {feedback ? <Text accessibilityRole={valid ? undefined : 'alert'} accessibilityLiveRegion="polite" style={valid ? styles.text : styles.error}>{feedback}</Text> : null}
    <Action title="Back to home" onPress={() => router.replace('/home')} />
  </Screen>;
}
