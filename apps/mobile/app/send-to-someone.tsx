import { useEffect, useState } from 'react';
import { AppState, StyleSheet, Text, TextInput, View } from 'react-native';
import { router } from 'expo-router';
import { Action, Screen, styles } from '../components/ui';
import { validateDirectDraft } from '../lib/direct-draft';
import { DirectTimeReview, isDirectTimeReviewCurrent } from '../lib/direct-unlock-time';
import { useDirectFormScroll } from '../components/use-direct-form-scroll';

type Field = 'recipient' | 'title' | 'body' | 'dateTime';
const timezoneName = () => Intl.DateTimeFormat().resolvedOptions().timeZone || 'device local time';

export default function SendToSomeoneScreen() {
  const [recipient, setRecipient] = useState('');
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [date, setDate] = useState('');
  const [time, setTime] = useState('');
  const [error, setError] = useState<{ field: Field; message: string } | null>(null);
  const [notice, setNotice] = useState('');
  const [reviewed, setReviewed] = useState<DirectTimeReview | null>(null);
  const timezone = timezoneName();
  const { scrollRef, onFocus, onBlur, onFeedbackLayout, showFeedback } = useDirectFormScroll();

  useEffect(() => {
    if (!reviewed) return;
    const review = reviewed;
    let active = true;
    function invalidate() {
      if (!active) return;
      active = false;
      setReviewed(null);
      setNotice('Your reveal time needs to be checked again.');
    }
    function checkReview() {
      if (active && !isDirectTimeReviewCurrent(review, Date.now(), performance.now(), timezoneName())) invalidate();
    }
    const listener = AppState.addEventListener('change', (state) => {
      if (state !== 'active') invalidate();
      else checkReview();
    });
    if (AppState.currentState && AppState.currentState !== 'active') invalidate();
    else checkReview();
    const timer = setInterval(checkReview, 1000);
    return () => { active = false; clearInterval(timer); listener.remove(); };
  }, [reviewed]);

  function checkDetails() {
    const now = Date.now();
    const monotonic = performance.now();
    const result = validateDirectDraft({ recipient, title, body, date, time }, now);
    showFeedback();
    if (!result.ok) { setReviewed(null); setError({ field: result.field, message: result.error }); setNotice(''); return; }
    setError(null);
    setReviewed({ date, time, timezone: timezoneName(), offset: result.offset, utc: result.utc, wallClock: now, monotonicClock: monotonic });
    setNotice('Reveal time ready to review below. Sending is not available yet. Nothing has been sent.');
  }
  function clearFeedback(field: Field) {
    setError((current) => current?.field === field ? null : current);
    setNotice(''); setReviewed(null);
  }

  return <Screen scrollRef={scrollRef} topAligned>
    <Text accessibilityRole="header" style={styles.title}>Send to Someone</Text>
    <Text style={styles.text}>Sending capsules to someone is not available yet. You can check your details here.</Text>
    <Text style={styles.label}>Recipient email</Text>
    <TextInput accessibilityLabel="Recipient email" accessibilityHint={error?.field === 'recipient' ? error.message : undefined} style={styles.input} value={recipient} onFocus={onFocus} onBlur={onBlur}
      onChangeText={(value) => { setRecipient(value); clearFeedback('recipient'); }} keyboardType="email-address"
      autoCapitalize="none" autoCorrect={false} autoComplete="off" />
    <Text style={styles.label}>Title</Text>
    <TextInput accessibilityLabel="Title" accessibilityHint={error?.field === 'title' ? error.message : undefined} style={styles.input} value={title} onFocus={onFocus} onBlur={onBlur}
      onChangeText={(value) => { setTitle(value); clearFeedback('title'); }} />
    <Text style={styles.label}>Private message</Text>
    <TextInput accessibilityLabel="Private message" accessibilityHint={error?.field === 'body' ? error.message : undefined} style={styles.input} value={body} onFocus={onFocus} onBlur={onBlur}
      onChangeText={(value) => { setBody(value); clearFeedback('body'); }} multiline autoCorrect={false} autoComplete="off" />
    <Text style={styles.text}>{Array.from(body).length} / 2,000 characters</Text>
    <Text style={styles.label}>Local reveal date (YYYY-MM-DD)</Text>
    <TextInput accessibilityLabel="Local reveal date, year month day" accessibilityHint={error?.field === 'dateTime' ? error.message : 'Enter a date as year, month, day.'} style={styles.input} value={date} onFocus={onFocus} onBlur={onBlur}
      onChangeText={(value) => { setDate(value); clearFeedback('dateTime'); }} placeholder="YYYY-MM-DD" placeholderTextColor="#6A5C52" />
    <Text style={styles.label}>Local reveal time, 24-hour (HH:MM)</Text>
    <TextInput accessibilityLabel="Local reveal time, 24-hour hours and minutes" accessibilityHint={error?.field === 'dateTime' ? error.message : 'Enter a 24-hour time in hours and minutes.'} style={styles.input} value={time} onFocus={onFocus} onBlur={onBlur}
      onChangeText={(value) => { setTime(value); clearFeedback('dateTime'); }} placeholder="HH:MM" placeholderTextColor="#6A5C52" />
    <Text style={styles.text}>Timezone: {timezone}. Enter the local date and time on your device.</Text>
    <Action title="Check details" onPress={checkDetails} />
    <View onLayout={onFeedbackLayout} style={formStyles.feedback}>
      <Text accessibilityLiveRegion="polite" style={error ? styles.error : styles.text}>{error?.message || notice}</Text>
      {reviewed ? <>
        <Text accessibilityRole="header" style={styles.label}>Confirm reveal time</Text>
        <Text style={styles.text}>Local date: {reviewed.date}</Text>
        <Text style={styles.text}>Local time: {reviewed.time}</Text>
        <Text style={styles.text}>Timezone: {reviewed.timezone} ({reviewed.offset})</Text>
        <Text style={styles.text}>UTC equivalent: {reviewed.utc}</Text>
      </> : null}
    </View>
    <Action title="Back to home" onPress={() => router.replace('/home')} />
  </Screen>;
}

const formStyles = StyleSheet.create({ feedback: { gap: 20 } });
