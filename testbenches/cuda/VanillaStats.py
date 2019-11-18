import csv
from collections import Counter
import pandas as pd
from CudaTag import CudaTag
# Manycore dimensions - use X/Y min/max

# Each tile group has a unique ID. Each tile group has a start and
# finish which is indicated by the tile group id (as the tag in the
# csv), and tag + 0xDEAD0000 (We should have print_stats_start and
# print_stats_end)

@pd.api.extensions.register_dataframe_accessor("tileGroup")
class TileGroupAccessor():
    def __init__(self, pdo):
        self._pdo = pdo
    
    @classmethod
    def isTagFinal(cls, t):
        return ((t >> 31) & 1) == 1

    @classmethod
    def extractTileGroup(cls, t):
        return (t & 0xFFFF)

    @classmethod
    def extractTag(cls, t):
        return (t & 0xFFFF)

    @property
    def last(self):
        return self._pdo[self._pdo.tag.apply(self.isTagFinal)]

    def tag(self, s):
        return self._pdo[self._pdo.tag.apply(self.extractTag).isin(s)]

    def id(self, s):
        return self._pdo[self._pdo.tag.apply(self.extractTileGroup).isin(s)]
    

a = pd.read_csv('vanilla_stats.log')

print(a)
