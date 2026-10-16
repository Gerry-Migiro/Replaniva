"""Browser speech lifecycle, separate from planning and approval."""

import from react { useEffect, useRef }

obj SpeechSession {
    has listening: bool, supported: bool, error: str, speaking: bool,
        narration_supported: bool, start: any, speak: any, stop: any, cancel: any;
}

def:pub useSpeech(onTranscript: any) -> SpeechSession {
    has listening: bool = False, voice_supported: bool = True, voice_error: str = "",
        voice_heard: bool = False, speaking: bool = False, narration_supported: bool = True;
    recognition_ref: any = useRef(None);
    useEffect(lambda -> None {
        win: any = window;
        narration_supported = bool(win.speechSynthesis and win.SpeechSynthesisUtterance);
    }, []);

    def start_listening() -> None {
        try {
            if listening and recognition_ref.current {
                recognition_ref.current.abort();
                listening = False;
                voice_error = "Voice input cancelled. You can edit or submit the current text.";
                return;
            }
            voice_error = "";
            voice_heard = False;
            win: any = window;
            rec_cls: any = win.SpeechRecognition if win.SpeechRecognition else win.webkitSpeechRecognition;
            if not rec_cls {
                voice_supported = False;
                voice_error = "Voice recognition is not supported in this browser (supported in Chrome and Edge). Typed commands are fully available.";
                return;
            }
            recognition: any = new(rec_cls);
            recognition_ref.current = recognition;
            recognition.continuous = False;
            recognition.interimResults = True;
            recognition.onstart = lambda (e: any) -> None { listening = True; voice_error = ""; };
            recognition.onresult = lambda (e: any) -> None {
                transcript: str = "";
                if e and e.results {
                    for res in e.results {
                        if res and len(res) > 0 and res[0] {
                            transcript += res[0].transcript;
                        }
                    }
                }
                if transcript {
                    onTranscript(transcript);
                    voice_heard = True;
                }
            };
            recognition.onerror = lambda (e: any) -> None {
                error_code = str(e.error) if e and e.error else "";
                if error_code == "not-allowed" or error_code == "service-not-allowed" {
                    voice_error = "Microphone access was denied. Allow access or type the request.";
                } elif error_code == "no-speech" {
                    voice_error = "No speech was detected. Try again or type the request.";
                } elif error_code == "aborted" {
                    voice_error = "Voice input cancelled. You can edit or submit the current text.";
                } else {
                    voice_error = "Voice recognition failed. Try again or type the request.";
                }
                listening = False;
                recognition_ref.current = None;
            };
            recognition.onend = lambda (e: any) -> None {
                if listening and not voice_heard and not voice_error {
                    voice_error = "No speech was detected. Try again or type the request.";
                }
                listening = False;
                recognition_ref.current = None;
            };
            recognition.start();
        } except Exception {
            voice_error = "Could not start voice recognition.";
            listening = False;
        }
    }

    def cancel_listening() -> None {
        if recognition_ref.current {
            recognition_ref.current.onstart = None;
            recognition_ref.current.onresult = None;
            recognition_ref.current.onerror = None;
            recognition_ref.current.onend = None;
            recognition_ref.current.abort();
            recognition_ref.current = None;
        }
        listening = False;
    }

    def speak_text(text: str) -> None {
        try {
            win: any = window;
            synth: any = win.speechSynthesis;
            if not synth { return; }
            synth.cancel();
            utt_cls: any = win.SpeechSynthesisUtterance;
            if not utt_cls { return; }
            utterance: any = new(utt_cls, text);
            utterance.onend = lambda (e: any) -> None { speaking = False; };
            utterance.onerror = lambda (e: any) -> None { speaking = False; };
            speaking = True;
            synth.speak(utterance);
        } except Exception {}
    }
    def stop_speaking() -> None {
        try {
            win: any = window;
            synth: any = win.speechSynthesis;
            if not synth { return; }
            synth.cancel();
            speaking = False;
        } except Exception {}
    }

    useEffect(lambda {
        return lambda {
            if recognition_ref.current { recognition_ref.current.abort(); }
            win: any = window;
            if win.speechSynthesis { win.speechSynthesis.cancel(); }
        };
    }, []);
    return SpeechSession(listening=listening, supported=voice_supported, error=voice_error,
        speaking=speaking, narration_supported=narration_supported,
        start=start_listening, speak=speak_text, stop=stop_speaking, cancel=cancel_listening);
}
