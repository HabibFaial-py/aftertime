import { ActivityIndicator, StyleSheet, Text, View } from 'react-native';
import { canReveal, ReceivedState } from '../lib/received-capsules';
import { Action, styles } from './ui';

const statusText = {
  unavailable: 'Received capsules are not available yet.',
  loading: 'Loading received capsules…',
  error: 'Received capsules could not be loaded.',
  empty: 'No received capsules yet.',
  auth: 'Your session could not be verified. Sign in again to view received capsules.',
};

export function ReceivedCapsulesContent({ state, onRefresh, onReveal }: {
  state: ReceivedState;
  onRefresh?: () => void;
  onReveal?: (id: string) => void;
}) {
  if (state.phase !== 'ready') {
    const failed = state.phase === 'error' || state.phase === 'auth';
    return <>
      <Text accessibilityLiveRegion="polite" style={failed ? styles.error : styles.text}>{statusText[state.phase]}</Text>
      {state.phase === 'loading' && <ActivityIndicator accessible={false} importantForAccessibility="no" color="#A65338" />}
      {onRefresh && state.phase !== 'loading' && state.phase !== 'auth' &&
        <Action title={failed ? 'Retry' : 'Refresh inbox'} onPress={onRefresh} />}
    </>;
  }

  const { items, reveal } = state;
  return <>
    <Text style={styles.text}>Status reflects the last inbox refresh. Reveal checks whether the message is still available.</Text>
    {items.map((item) => <View key={item.id} style={receivedStyles.card}>
      <Text accessibilityRole="header" style={styles.label}>{item.status === 'locked' ? 'Locked capsule' : 'Unlocked capsule'}</Text>
      <Text style={styles.text}>Reveal time: {new Date(item.unlock_at).toLocaleString()}</Text>
      <Text style={styles.text}>Created: {new Date(item.created_at).toLocaleString()}</Text>
      <Text style={styles.text}>Sender ID: {item.sender_id}</Text>
      {onReveal && canReveal(item, reveal) && <Action title="Reveal message" onPress={() => onReveal(item.id)} />}
    </View>)}
    {reveal.phase === 'revealing' && <>
      <Text accessibilityLiveRegion="polite" style={styles.text}>Revealing message…</Text>
      <ActivityIndicator accessible={false} importantForAccessibility="no" color="#A65338" />
    </>}
    {reveal.phase === 'unavailable' && <Text accessibilityLiveRegion="polite" style={styles.error}>This capsule is unavailable. Refresh your inbox.</Text>}
    {reveal.phase === 'uncertain' && <Text accessibilityLiveRegion="polite" style={styles.error}>Reveal could not be confirmed. Refresh your inbox before trying again.</Text>}
    {reveal.phase === 'revealed' && <View style={receivedStyles.card}>
      <Text accessibilityRole="header" accessibilityLiveRegion="polite" style={styles.label}>Revealed message</Text>
      <Text style={styles.text}>{reveal.body}</Text>
    </View>}
    {onRefresh && <Action title="Refresh inbox" onPress={onRefresh} />}
  </>;
}

const receivedStyles = StyleSheet.create({
  card: { backgroundColor: '#FFFFFF', borderColor: '#DCC8B9', borderWidth: 1, borderRadius: 12, padding: 18, gap: 6 },
});
