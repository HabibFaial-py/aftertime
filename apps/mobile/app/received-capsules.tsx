import { Text } from 'react-native';
import { router } from 'expo-router';
import { ReceivedCapsulesContent } from '../components/received-capsules';
import { Action, Screen, styles } from '../components/ui';

export default function ReceivedCapsulesScreen() {
  return <Screen topAligned>
    <Text accessibilityRole="header" style={styles.title}>Received Capsules</Text>
    <ReceivedCapsulesContent state="unavailable" />
    <Action title="Back to home" onPress={() => router.replace('/home')} />
  </Screen>;
}
