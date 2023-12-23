import numpy as np
import matplotlib.pyplot as plt

# n_adj =
# n_col =

fig, axs = plt.subplots(2, 2)

# adj_norm
x1 = np.linspace(0, 1, 100)
y1 = np.power(x1, 4)
axs[0, 0].set_title("adj_norm")
axs[0, 0].plot(x1, y1)
axs[0, 0].set_xlim([0, 1])
axs[0, 0].set_ylim([0, 1])

# col_norm
x2 = np.linspace(0, 1, 100)
y2 = ((0.8 - 0.2) * np.power(x2, 5) + 0.2)
axs[0, 1].set_title("col_norm")
axs[0, 1].plot(x2, y2)
axs[0, 1].set_xlim([0, 1])
axs[0, 1].set_ylim([0, 1])

# Heat map
#heat_map = np.outer(y1, y2)
heat_map = np.maximum.outer(y1, y2)
axs[1, 0].set_xlabel("col_norm")
axs[1, 0].set_ylabel("adj_norm")
axs[1, 0].set_title("f(p)")
axs[1, 0].imshow(heat_map, cmap='hot', interpolation="nearest")

#
plt.show()
