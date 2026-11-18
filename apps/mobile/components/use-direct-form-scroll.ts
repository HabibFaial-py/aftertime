import { ComponentRef, useEffect, useRef } from 'react';
import { Keyboard, LayoutChangeEvent, ScrollView, TextInputFocusEvent } from 'react-native';

// Scroll only after an input receives keyboard focus, or after the user checks details.
export function useDirectFormScroll() {
  const scrollRef = useRef<ComponentRef<typeof ScrollView> | null>(null);
  const focused = useRef<number | null>(null);
  const feedbackY = useRef<number | null>(null);
  const focusFrame = useRef<number | null>(null);
  const feedbackFrame = useRef<number | null>(null);

  function cancelFocus() {
    if (focusFrame.current !== null) cancelAnimationFrame(focusFrame.current);
    focusFrame.current = null;
  }
  function cancelFeedback() {
    if (feedbackFrame.current !== null) cancelAnimationFrame(feedbackFrame.current);
    feedbackFrame.current = null;
  }
  function revealFocusedInput() {
    if (focused.current === null) return;
    cancelFocus();
    focusFrame.current = requestAnimationFrame(() => {
      focusFrame.current = null;
      if (focused.current !== null) {
        scrollRef.current?.scrollResponderScrollNativeHandleToKeyboard(focused.current, 24, true);
      }
    });
  }
  useEffect(() => {
    const shown = Keyboard.addListener('keyboardDidShow', revealFocusedInput);
    const hidden = Keyboard.addListener('keyboardDidHide', cancelFocus);
    return () => { shown.remove(); hidden.remove(); focused.current = null; cancelFocus(); cancelFeedback(); };
  // The handlers use stable refs and need only one pair of keyboard listeners.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function onFocus(event: TextInputFocusEvent) {
    cancelFeedback();
    focused.current = event.nativeEvent.target;
    if (Keyboard.isVisible()) revealFocusedInput();
  }
  function onBlur(event: TextInputFocusEvent) {
    if (focused.current === event.nativeEvent.target) { focused.current = null; cancelFocus(); }
  }
  function onFeedbackLayout(event: LayoutChangeEvent) { feedbackY.current = event.nativeEvent.layout.y; }
  function showFeedback() {
    focused.current = null;
    cancelFocus(); cancelFeedback();
    feedbackFrame.current = requestAnimationFrame(() => {
      feedbackFrame.current = null;
      if (feedbackY.current !== null) scrollRef.current?.scrollTo({ y: Math.max(0, feedbackY.current - 24), animated: true });
    });
  }
  return { scrollRef, onFocus, onBlur, onFeedbackLayout, showFeedback };
}
