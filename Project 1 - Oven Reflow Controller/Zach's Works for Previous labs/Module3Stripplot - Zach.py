import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import sys, time, math
import serial

ser = serial.Serial(
    port='COM4',
    baudrate=115200,
    parity=serial.PARITY_NONE,
    stopbits=serial.STOPBITS_TWO,
    bytesize=serial.EIGHTBITS
)

xsize=500
cumsum = 1
cumaverage = 1
   
def data_gen():
    t = 0
    tempsum = 0
    while True:
       t+=1
       tempin = float(ser.readline())
       temp=tempin/10000.0
       tempsum += temp
       if t <= 0:
           tempavg = tempsum
       else:
           tempavg = tempsum/t
       yield t, temp, tempavg

def run(data):
    # update the data
    t,y1,y2 = data
    if t>-1:
        xdata.append(t)
        y1data.append(y1)
        y2data.append(y2)
        if t>xsize: # Scroll to the left.
            ax.set_xlim(t-xsize, t)
        line1.set_data(xdata, y1data)
        line2.set_data(xdata, y2data)
    return line1, line2,

def on_close_figure(event):
    sys.exit(0)

data_gen.t = -1
fig = plt.figure()
fig.canvas.mpl_connect('close_event', on_close_figure)
ax = fig.add_subplot(111)
line1, = ax.plot([], [], lw=2)
line2, = ax.plot([], [], lw=2)
ax.set_ylim(0,100)
ax.set_xlim(0, xsize)
ax.grid()
xdata, y1data, y2data = [], [], []

# Important: Although blit=True makes graphing faster, we need blit=False to prevent
# spurious lines to appear when resizing the stripchart.
ani = animation.FuncAnimation(fig, run, data_gen, blit=False, interval=100, repeat=False)
plt.show()
