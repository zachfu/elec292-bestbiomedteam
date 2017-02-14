import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import sys, time, math
import matplotlib
from matplotlib.collections import LineCollection
from matplotlib.colors import ListedColormap, BoundaryNorm

xsize=100

def data_gen():
    t = data_gen.t
    while True:
       t+=1
       val=50.0*math.sin(t*2.0*3.1415/100.0)
       yield t, val

def run(data):
    # update the data
    t,y = data
    #if t>xsize: # Scroll to the left.
    #    ax.set_xlim(t-xsize, t)
    if t>-1 and t<20:         
        xdata.append(t)
        ydata.append(y)
        line.set_data(xdata, ydata)
    if t>=20 and t<40:
        xdata1.append(t)
        ydata1.append(y)
        line1.set_data(xdata1, ydata1)
    if t>=40 and t<60:
        xdata2.append(t)
        ydata2.append(y)
        line2.set_data(xdata2, ydata2)
    if t>=60 and t<80:
        xdata3.append(t)
        ydata3.append(y)
        line3.set_data(xdata3, ydata3)
    if t>=80 and t<1000:
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
ax.set_axis_bgcolor('k')

ax.set_ylim(-100, 100)
ax.set_xlim(0, xsize)
ax.grid()
line, = ax.plot([], [], '-',color='r',lw=4,label='Ramp to Soak')
line1, = ax.plot([], [], '-.',color='r',lw=4,label='Soak')
line2, = ax.plot([], [], '-',color='yellow',lw=4,label='Ramp to Reflow')
line3, = ax.plot([], [], '-.',color='yellow',lw=4,label='Reflow')
line4, = ax.plot([], [], '-',color='b',lw=4,label='Cooling')
legend = ax.legend(loc='upper left', shadow=True)
gridlines = ax.get_xgridlines() + ax.get_ygridlines()
ticklabels = ax.get_xticklabels() + ax.get_yticklabels()
frame = legend.get_frame()
frame.set_facecolor('0.9')
plt.ylabel('Temperature(°C)')
plt.xlabel('Time(s)')
plt.title('Real-time Temperature monitoring')
xdata, ydata = [], []
xdata1, ydata1 = [], []
xdata2, ydata2 = [], []
xdata3, ydata3 = [], []
xdata4, ydata4 = [], []

for label in legend.get_texts():
    label.set_fontsize('medium')

for label in legend.get_lines():
    label.set_linewidth(1.5)

for lline in gridlines:
    lline.set_linestyle('-.')
    lline.set_color('gray')
    lline.set_linewidth(1)
    
for label in ticklabels:
    label.set_color('darkgreen')
    label.set_fontsize('large')
    

# Important: Although blit=True makes graphing faster, we need blit=False to prevent
# spurious lines to appear when resizing the stripchart.
ani = animation.FuncAnimation(fig, run, data_gen, blit=False, interval=100, repeat=False)
plt.show()

plt.show()

