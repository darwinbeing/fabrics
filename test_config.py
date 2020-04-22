import random
import yaml
import sys
import subprocess

design = sys.argv[1]
test_count = int(sys.argv[2])

for c in range(test_count):
    config = dict()
    config['wd_id'] = random.randint(0,32)
    config['wd_addr'] = random.randint(20,64)
    config['wd_data'] = random.choice([32, 64, 128, 256, 512, 1024])
    config['wd_user'] = random.randint(0, 32)
    config['tn_num_masters'] = random.randint(1, 16)
    config['tn_num_slaves'] = random.randint(1, 16)
    config['fixed_priority_rd'] = random.randint(0,config['tn_num_masters'] )
    config['fixed_priority_wr'] = random.randint(0,config['tn_num_masters'] )
    config['memory_map'] = dict()
    mem_start = 0x1000
    error_access_id = random.randint(0, config['tn_num_slaves']-1)
    for i in range(config['tn_num_slaves']):
        config['memory_map'][i] = dict()
        if i == error_access_id:
            config['memory_map'][i]['access'] = 'error'
        else:
            config['memory_map'][i]['base'] = mem_start
            config['memory_map'][i]['bound'] = mem_start+ 0x1000
            config['memory_map'][i]['access'] = random.choice(['read-only', 'write-only', 'read-write'])
            mem_start = mem_start + 0x2000
    
    if design == 'axi4':
        with open('axi4/test/axi4_crossbar_config.yaml', 'w') as outfile:
            yaml.dump(config, outfile, default_flow_style=False, allow_unicode=True)
        make_process = subprocess.Popen("make -C {0}/test clean; make -C {0}/test TOP_FILE={0}_crossbar.bsv TOP_MODULE=mk{0}_crossbar generate_instances".format(design), shell=True, stderr=subprocess.STDOUT)
    if design == 'axi4l':
        with open('axi4_lite/test/axi4l_crossbar_config.yaml', 'w') as outfile:
            yaml.dump(config, outfile, default_flow_style=False, allow_unicode=True)
        make_process = subprocess.Popen("make -C axi4_lite/test clean; make -C axi4_lite/test TOP_FILE={0}_crossbar.bsv TOP_MODULE=mk{0}_crossbar generate_instances".format(design), shell=True, stderr=subprocess.STDOUT)
    if design == 'apb':
        with open('apb/test/apb_interconnect_config.yaml', 'w') as outfile:
            yaml.dump(config, outfile, default_flow_style=False, allow_unicode=True)
            make_process = subprocess.Popen("make -C {0}/test clean; make -C {0}/test TOP_FILE={0}_interconnect.bsv TOP_MODULE=mk{0}_interconnect generate_instances".format(design), shell=True, stderr=subprocess.STDOUT)

    if make_process.wait() != 0:
        print('ERROR: Did not compile {0}'.format(design))
        sys.exit(1)
