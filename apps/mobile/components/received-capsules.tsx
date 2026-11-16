import { ActivityIndicator, Text } from 'react-native';
import { styles } from './ui';

// These states are presentation only until a reviewed recipient service exists.
export type ReceivedState = 'unavailable' | 'loading' | 'error' | 'empty';

export function ReceivedCapsulesContent({ state }: { state: ReceivedState }) {
  return <>
    {state === 'unavailable' && <Text style={styles.text}>Received capsules are not available yet.</Text>}
    {state === 'loading' && <ActivityIndicator accessibilityLabel="Loading received capsules" color="#A65338" />}
    {state === 'error' && <Text accessibilityRole="alert" style={styles.error}>Received capsules could not be loaded.</Text>}
    {state === 'empty' && <Text style={styles.text}>You have no received capsules yet.</Text>}
    <Text accessibilityRole="header" style={styles.label}>Pending</Text>
    <Text style={styles.text}>Pending capsules will appear here when available.</Text>
    <Text accessibilityRole="header" style={styles.label}>Claimed</Text>
    <Text style={styles.text}>Claimed capsules will appear here when available.</Text>
  </>;
}
