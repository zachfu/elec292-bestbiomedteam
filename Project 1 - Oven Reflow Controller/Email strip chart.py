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
 
#ser = serial.Serial(
    #port='COM4',
    #baudrate=115200,
    #parity=serial.PARITY_NONE,
    #stopbits=serial.STOPBITS_TWO,
    #bytesize=serial.EIGHTBITS
#)

xsize=1000
cumsum = 1
cumaverage = 1
def email_send():
    fromaddr = "elec292bestbiomedteam@gmail.com"
    toaddr = "zachfu97@gmail.com"               # CHANGE THIS TO YOUR EMAIL THAT WILL RECEIVE THE MESSAGE
     
    msg = MIMEMultipart()
     
    msg['From'] = fromaddr
    msg['To'] = toaddr
    msg['Subject'] = "ATTACHMENT TEST"
     
    body = "SEE DAT IMAGE YO"
     
    msg.attach(MIMEText(body, 'plain'))
     
    filename = "test.png"
    attachment = open('test.png', "rb")   
     
    part = MIMEBase('application', 'octet-stream')
    part.set_payload((attachment).read())
    encoders.encode_base64(part)
    part.add_header('Content-Disposition', "attachment; filename= %s" % filename)
     
    msg.attach(part)
     
    server = smtplib.SMTP('smtp.gmail.com', 587)
    server.starttls()
    server.login(fromaddr, "praisejesus")
    text = msg.as_string()
    server.sendmail(fromaddr, toaddr, text)
    server.quit()


def data_gen():
    t = 0
    while True:
       t+=1
       y = 50+25*math.sin(0.1*t)    # PLACEHOLDER DATA TO BE PLOTTED
       if t == 100:
           plt.savefig('test.png')
           email_send()
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
ax.set_ylim(0,100)
ax.set_xlim(0, xsize)
ax.grid()
xdata, ydata = [], []

# Important: Although blit=True makes graphing faster, we need blit=False to prevent
# spurious lines to appear when resizing the stripchart.
ani = animation.FuncAnimation(fig, run, data_gen, blit=False, interval=100, repeat=False)
plt.show()
