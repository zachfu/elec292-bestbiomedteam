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

import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import sys, time, math
import serial
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.base import MIMEBase
from email import encoders
import webbrowser
import csv

ser = serial.Serial(
    port='COM4',
    baudrate=115200,
    parity=serial.PARITY_NONE,
    stopbits=serial.STOPBITS_TWO,
    bytesize=serial.EIGHTBITS
)

xsize=1000


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


def email_send(msgID, filename):
    """sends an email to the reciever"""
    fromaddr = "elec292bestbiomedteam@gmail.com"
    toaddr = "danielzhou4970@gmail.com"# CHANGE THIS TO YOUR EMAIL THAT WILL RECEIVE THE MESSAGE

    msg = MIMEMultipart()

    msg['From'] = fromaddr
    msg['To'] = toaddr
    msg['Subject'], body = msgID_Handler(msgID)
    
    msg.attach(MIMEText(body, 'plain')) 
    msg.attach(make_attachment(filename))

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

def data_gen():
    t = 0
    email_sent = 0
    with open('ReflowProcess.csv', 'w') as csvfile:
        fieldnames = ['Time', 'Process_Time [s]', 'State', 'Temperature [centigrade]']
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
            writer.writerow({'Process_Time [s]': t, 'State': get_state_string(state), 'Temperature [Centigrade]': temp})
            ended, msgID = get_Msg_ID(state)
            state_prev = state
    
            if ended is True and email_sent != 1:
                email_sent = 1
                filename = fileName_Handler(msgID)
                plt.savefig(filename)
                email_send(msgID, filename)
                if state == 15:
                    webbrowser.open('https://www.youtube.com/watch?v=-YCN-a0NsNk')
    
            yield t, temp

def run(data):
    # update the data
    t, y = data
    if t > -1:
        xdata.append(t)
        ydata.append(y)
        if t > xsize:  # Scroll to the left.
            ax.set_xlim(t-xsize, t)
        line1.set_data(xdata, ydata)
    return line1


def on_close_figure(event):
    sys.exit(0)

data_gen.t = -1
fig = plt.figure()
fig.canvas.mpl_connect('close_event', on_close_figure)
ax = fig.add_subplot(111)
line1, = ax.plot([], [], lw=2)
ax.set_ylim(0,300)
ax.set_xlim(0, xsize)
ax.grid()
xdata, ydata = [], []

# Important: Although blit=True makes graphing faster, we need blit=False to prevent
# spurious lines to appear when resizing the stripchart.
ani = animation.FuncAnimation(fig, run, data_gen, blit=False, interval=100, repeat=False)
plt.show()
