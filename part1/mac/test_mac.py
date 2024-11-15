import pytest
import queue
import os
import pytest_utils
from pytest_utils.decorators import max_score, visibility, tags
  
import sys
_REPO_ROOT = os.getenv('REPO_ROOT')
assert (_REPO_ROOT), "REPO_ROOT must be defined in environment as a non-empty string"
assert (os.path.exists(_REPO_ROOT)), "REPO_ROOT path must exist"
sys.path.append(os.path.join(_REPO_ROOT, "util"))
from utilities import *

from cocotb_test.simulator import run
import cocotb
from cocotb.clock import Clock
from cocotb.regression import TestFactory
from cocotb.utils import get_sim_time
from cocotb.triggers import Timer, ClockCycles, RisingEdge, FallingEdge, with_timeout, First
from cocotb.types import LogicArray, Range
import json
import random
import numpy as np
random.seed(42)

from itertools import product

DIR_PATH = os.path.dirname(os.path.realpath(__file__))
   
timescale = "1ps/1ps"

@max_score(9)
def test_all_runner():
    # This line must be first
    parameters = dict(locals())
    runner(timescale, DIR_PATH, None, parameters, ds=[f'HEXPATH="{DIR_PATH}/"'], top="testbench")

@cocotb.test()
async def run_test(dut):
    await Timer(1, units="ns")

    # You must set these to 0 before testing!
    assert_passerror(dut.error_o)
    assert_passerror(dut.pass_o)

    # But only set them when you're certain the target module passes/fails!
    await First(RisingEdge(dut.error_o), RisingEdge(dut.pass_o))
    print(f"Cocotb saw: error_o: {dut.error_o.value}, pass_o: {dut.pass_o.value}")
