port speech_recognition as sr
import pyaudio



print "say something1"
r = sr.Recognizer()
r.dynamic_energy_threshold
with sr.Microphone() as source:                # use the default microphone as the audio source
    print "say something"
    audio = r.record(source,duration=3)                   # listen for the first phrase and extract it into audio data

try:
    print("You said " + r.recognize_sphinx(audio))    # recognize speech using Google Speech Recognition
except LookupError:                            # speech is unintelligible
    print("Could not understand audio")


 #things to install
    #pip install pyaudio (also need to make sure to update to latest version)
    #pip install pocketsphinx
    #pip install speechrecognition
    #https://pypi.python.org/pypi/SpeechRecognition/ (link for speech recognition library)
