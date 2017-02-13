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
 
ser = serial.Serial(
    port='COM4',
    baudrate=115200,
    parity=serial.PARITY_NONE,
    stopbits=serial.STOPBITS_TWO,
    bytesize=serial.EIGHTBITS
)

xsize=1000
cumsum = 1
cumaverage = 1


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
    """msgID 0=error, 1=update, 2=complete, 3=aborted process"""
    subjectType = {
        0: "ERROR ALERT!!!",
        1: "UPDATE",
        2: "COMPLETION",
        3: "CANCELATION ALERT!!",
    }
    bodyType = {
        0: "Error occured during the process. Last moment attached",
        1: "Last Update of the process attached",
        2: "Process successfully completed. CSV file and graph are attached",
        3: "your process has been manually cancelled. Attached documents",
    }

    return subjectType.get(msgID, "No Subject"), bodyType.get(msgID, "No Body")

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


def data_gen():
    t = 0
    email_sent = 0
    while True:
       t+=1
       y = float(ser.readline())
       if y >= 220 and not email_sent:
           plt.savefig('test.png')
           email_send( 1, 'test.png')
           email_sent = 1
       yield t, y

def run(data):
    # update the data
    t,y = data
    if t>-1:
        xdata.append(t)
        ydata.append(y)
        if t>xsize: # Scroll to the left.
            ax.set_xlim(t-xsize, t)
        line1.set_data(xdata, ydata)
    return line1,

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
