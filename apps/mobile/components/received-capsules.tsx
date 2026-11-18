import { ActivityIndicator, Text } from 'react-native';
import { Action, styles } from './ui';

// Presentation only. A future caller should use 'empty' only when both lists are known to be empty.
export type ReceivedState = 'unavailable' | 'loading' | 'error' | 'empty';

const statusText: Record<ReceivedState, string> = {
  unavailable: 'Received capsules are not available yet.',
  loading: 'Loading received capsules…',
  error: 'Received capsules could not be loaded.',
  empty: 'Nothing here yet.',
};

// A retry is shown only when a future caller provides a real recovery action.
export function ReceivedCapsulesContent({ state, onRetry }: { state: ReceivedState; onRetry?: () => void }) {
  return <>
    <Text accessibilityLiveRegion="polite" style={state === 'error' ? styles.error : styles.text}>{statusText[state]}</Text>
    {state === 'loading' && <ActivityIndicator accessible={false} importantForAccessibility="no" color="#A65338" />}
    {state === 'error' && onRetry && <Action title="Retry" onPress={onRetry} />}
    {(state === 'unavailable' || state === 'empty') && <>
      <Text accessibilityRole="header" style={styles.label}>Pending</Text>
      <Text style={styles.text}>{state === 'empty' ? 'No pending invitations.' : 'Pending invitations will appear here when available.'}</Text>
      <Text accessibilityRole="header" style={styles.label}>Claimed</Text>
      <Text style={styles.text}>{state === 'empty' ? 'No received capsules.' : 'Received capsules will appear here when available.'}</Text>
    </>}
  </>;
}
