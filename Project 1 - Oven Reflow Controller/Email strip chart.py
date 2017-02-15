# -*- coding: utf-8 -*-
"""
to run this python file, please make the following change in the assembly code:
    
; in taking the sample subroutine, make this change please:
    
    
;sending Oven temperature to Computer
Send_Serial:
	Send_BCD(bcd+1)
	Send_BCD(bcd)
	mov a, #'\n'
	lcall putchar
	
 +++++++++++++++++++++++++++++++++++++++ new part starts
	;sending the state to computer
	Move_1B_to_4B (x, state)
	lcall hex2bcd
	Send_BCD(bcd)
	mov a, #'\n'
	lcall putchar	
---------------------------------------- new part ends
ret
"""

"""
run 'pip install twilio' in Python terminal to enable sending text messages
"""

import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import sys, time
import serial
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.base import MIMEBase
from email import encoders
import webbrowser
import pyttsx
import csv
from twilio.rest import TwilioRestClient
import speech_recognition as sr
import pyaudio

ser = serial.Serial(
    port='COM4',
    baudrate=115200,
    parity=serial.PARITY_NONE,
    stopbits=serial.STOPBITS_TWO,
    bytesize=serial.EIGHTBITS
)
engine = pyttsx.init()
xsize=1000
account_sid = "ACfc81dca730513b75df2e4c12ca6803bf"
auth_token = "dc2928b0ca4fe591930b0a2d25216d55"
client = TwilioRestClient(account_sid, auth_token)

global state

def make_attachment(filename):
    """for attaching a file"""
    attachment = open(filename, "rb")
    part = MIMEBase('application', 'octet-stream')
    part.set_payload((attachment).read())
    encoders.encode_base64(part)
    part.add_header('Content-Disposition', "attachment; filename= %s" % filename)
    return part


def msgID_Handler(msgID):
    """different Subject line and Bodies of email based on the message ID"""
    subjectType = {
        15: "COMPLETION",
        16: "ERROR ALERT!!!",
        17: "CANCELATION ALERT!!",
    }
    bodyType = {
        15: "Process successfully completed. CSV file and graph are attached",
        16: "Error occured during the process. Last moment attached",
        17: "your process has been manually cancelled. Attached documents",
    }

    return subjectType.get(msgID, "No Subject"), bodyType.get(msgID, "No Body")


def fileName_Handler(msgID):
    """different filenames for email based on the message ID"""
    imageName = {
        15: "COMPLETION.png",
        16: "ERROR.png",
        17: "CANCELATION.png",
    }
    return imageName.get(msgID, "unDefined.png")


def email_send(msgID, filename1, filename2):
    """sends an email to the reciever"""
    fromaddr = "elec292bestbiomedteam@gmail.com"
    toaddr = "danielzhou4970@gmail.com"# CHANGE THIS TO YOUR EMAIL THAT WILL RECEIVE THE MESSAGE

    msg = MIMEMultipart()

    msg['From'] = fromaddr
    msg['To'] = toaddr
    msg['Subject'], body = msgID_Handler(msgID)
    
    msg.attach(MIMEText(body, 'plain')) 
    msg.attach(make_attachment(filename1))
    msg.attach(make_attachment(filename2))

    server = smtplib.SMTP('smtp.gmail.com', 587)
    server.starttls()
    server.login(fromaddr, "praisejesus")
    text = msg.as_string()
    server.sendmail(fromaddr, toaddr, text)
    server.quit()


def get_Msg_ID(state):
    """to determine if sending email is necessary and what msgID it has"""
    # if process is completed or aborted manualy or due to error
    if (state == 15 or state == 16 or state == 17):
        return True, state,
    # if process stage has changed
    else:
        return False, 1


def get_state_string(state):
    """to generate a string for states, used in CSV, and TextToSpeach modules"""
    stateName = {
        10: "Ramp to Soak",
        11: "Soak",
        12: "Ramp to reflow",
        13: "Reflow",
        14: "Cooling",
        15: "Finished",
        16: "Error",
        17: "Cancelled",
    }
    if state < 10:
        return "Initialization"
    else:
        return stateName.get(state)
def text_to_speech(state):
    if state == 10:
        engine.say('Process has started. Ensure oven door is closed. State Ramp to Soak.')
        engine.runAndWait()
        client.messages.create(from_="+17786537756", to="+17783184871",body='Process has Started!')
    if state == 11:
        engine.say('Process is now in soak stage')
        engine.runAndWait()
    if state == 12:
        engine.say('Process is now in ramp to reflow stage')
        engine.runAndWait()
    if state == 13:
        engine.say('Process is now in reflow')
        engine.runAndWait()
    if state == 14:
        engine.say('Now cooling. Please open oven door')
        engine.runAndWait()
    if state == 15:
        engine.say('Process complete. Please remove board from oven')
        engine.runAndWait()
    if state == 16:
        engine.say('Process aborted. Check thermocouple')
        engine.runAndWait()
        webbrowser.open('https://www.youtube.com/watch?v=9Deg7VrpHbM')
        client.messages.create(from_="+17786537756", to="+17783184871",body='Process Aborted!')
    if state == 17:
        engine.say('Process cancelled')
        engine.runAndWait()
        webbrowser.open('https://www.youtube.com/watch?v=Le9sLw2VdUg')
        client.messages.create(from_="+17786537756", to="+17783184871",body='Process Cancelled!')


def speech_to_text(state):
    r = sr.Recognizer()
    r.dynamic_energy_threshold=True
    with sr.Microphone() as source:                # use the default microphone as the audio source
        r.adjust_for_ambient_noise(source, duration = 1)
        print ("say something")
        audio = r.listen(source,timeout=3)                   # listen for the first phrase and extract it into audio data
    try:
        print("You said " + r.recognize_google(audio))    # recognize speech using Google Speech Recognition
        var=r.recognize_google(audio)
        if var == 'State' or 'States':
            print(get_state_string(state))
            engine.say("Your current state is" + get_state_string(state))
            engine.runAndWait()
        if var == 'Bush did 9/11':
            engine.say("Yes I agree with you")
            engine.runAndWait()
    except sr.UnknownValueError:
        print("Google Speech Recognition could not understand audio")
    except sr.RequestError as e:
        print("Could not request results from Google Speech Recognition service; {0}".format(e))


def data_gen():
    t = 0
    email_sent = 0
    global state
    with open('ReflowProcess.csv', 'w') as csvfile:
        fieldnames = ['Time', 'Process_Time [s]', 'State', 'Temperature [Centigrade]']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()

        while True:
            t += 1
    
            temp = float(ser.readline())
            if temp <= 17:
                temp = float(ser.readline())	# in case serial inputs aren't lined up properly
    
            state = int(ser.readline())
            if t == 1:
                state_prev = state
            writer.writerow({'Time': time.ctime(time.time()),'Process_Time [s]': t, 'State': get_state_string(state), 'Temperature [Centigrade]': temp})
            ended, msgID = get_Msg_ID(state)
            if state_prev != state:
                text_to_speech(state)
            state_prev = state

            speech_to_text(state)

            if ended is True and email_sent != 1:
                email_sent = 1
                filename = fileName_Handler(msgID)
                plt.savefig(filename)
                email_send(msgID, filename, "ReflowProcess.csv")
                if state == 15:
                    client.messages.create(from_="+17786537756", to="+17783184871",body='Reflow Process Done!')
                    webbrowser.open('https://www.youtube.com/watch?v=-YCN-a0NsNk')
    
            yield t, temp

def run(data):
    # update the data
    t, y = data
    if t > xsize:  # Scroll to the left.
            ax.set_xlim(t-xsize, t)
    if state==10:         
        xdata.append(t)
        ydata.append(y)
        line.set_data(xdata, ydata)
    if state==11:
        xdata1.append(t)
        ydata1.append(y)
        line1.set_data(xdata1, ydata1)
    if state==12:
        xdata2.append(t)
        ydata2.append(y)
        line2.set_data(xdata2, ydata2)
    if state==13:
        xdata3.append(t)
        ydata3.append(y)
        line3.set_data(xdata3, ydata3)
    if state==14:
        xdata4.append(t)
        ydata4.append(y)
        line4.set_data(xdata4, ydata4)
    return line,line1,line2,line3,line4,


def on_close_figure(event):
    sys.exit(0)

data_gen.t = -1
fig = plt.figure()
fig.canvas.mpl_connect('close_event', on_close_figure)
ax = fig.add_subplot(111)
ax.set_axis_bgcolor('k')    #set background color:black
line, = ax.plot([], [], '-.',color='yellow',lw=3,label='Ramp to Soak')
line1, = ax.plot([], [], '-',color='yellow',lw=3,label='Soak')
line2, = ax.plot([], [], '-.',color='r',lw=3,label='Ramp to Reflow')
line3, = ax.plot([], [], '-',color='r',lw=3,label='Reflow')
line4, = ax.plot([], [], '-',color='dodgerblue',lw=3,label='Cooling')
legend = ax.legend(loc='upper left', shadow=True)   #initiate legend
gridlines = ax.get_xgridlines() + ax.get_ygridlines()
ticklabels = ax.get_xticklabels() + ax.get_yticklabels()
frame = legend.get_frame()
frame.set_facecolor('0.9')
plt.ylabel('Temperature(C)')
plt.xlabel('Time(quarter seconds)')
plt.title('Real-time Temperature monitoring')
ax.set_ylim(0,300)
ax.set_xlim(0, xsize)
ax.grid(True)
xdata, ydata = [], []
xdata1, ydata1 = [], []
xdata2, ydata2 = [], []
xdata3, ydata3 = [], []
xdata4, ydata4 = [], []
"""
set the legend, ticklabels and grid lines
"""
for label in legend.get_texts():
    label.set_fontsize('medium')

for label in legend.get_lines():
    label.set_linewidth(1.5)

for lline in gridlines:
    lline.set_linestyle('-.')
    lline.set_color('gray')
    lline.set_linewidth(1)
    
for label in ticklabels:
    label.set_color('b')
    label.set_fontsize('large')

# Important: Although blit=True makes graphing faster, we need blit=False to prevent
# spurious lines to appear when resizing the stripchart.
ani = animation.FuncAnimation(fig, run, data_gen, blit=False, interval=100, repeat=False)
plt.show()
