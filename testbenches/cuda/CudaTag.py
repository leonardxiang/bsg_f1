# Number of tile groups = set(map(lambda x: if not x.isTileGroupFinish, a.tag.values))
from pandas.api.extensions import register_extension_dtype
from pandas.api.extensions import ExtensionDtype

import numpy as np
@register_extension_dtype
class CudaTag(ExtensionDtype):
    __FINISH_FLAG = int('DEAD0000', 16)
    def __new__(cls, t, *args, **kwargs):
        return  super(CudaTag, cls).__new__(cls, t)
        
    @property
    def isFinishTag(self):
        return self >= __FINISH_FLAG

    @property
    def isStartTag(self):
        return self < __FINISH_FLAG
