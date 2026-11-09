// SysBase pilot host: exact uint32 matrix reference and explicit kernel error checks.
#include <xrt/xrt_bo.h>
#include <xrt/xrt_device.h>
#include <xrt/xrt_kernel.h>
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <map>
#include <limits>
#include <random>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

using Clock = std::chrono::steady_clock;
double ms(Clock::time_point a, Clock::time_point b) {
    return std::chrono::duration<double, std::milli>(b-a).count();
}
std::vector<uint32_t> matrix(const std::string& path, unsigned dim) {
    std::ifstream file(path);
    if(!file) throw std::runtime_error("Cannot open input matrix: "+path);
    std::vector<uint32_t> result;
    std::string line;
    unsigned rows=0;
    while(std::getline(file,line)) {
        std::replace(line.begin(),line.end(),',',' ');
        std::istringstream row(line); int64_t value; unsigned columns=0;
        while(row>>value) {result.push_back(static_cast<uint32_t>(value));++columns;}
        if(columns!=dim) throw std::runtime_error("Input matrix width mismatch");
        ++rows;
    }
    if(rows!=dim) throw std::runtime_error("Input matrix height mismatch");
    return result;
}
int main(int argc,char** argv) {
  try {
    std::map<std::string,std::string> opt;
    for(int i=1;i<argc;i+=2) {
      if(i+1>=argc) throw std::runtime_error("Arguments require values");
      opt[argv[i]]=argv[i+1];
    }
    const unsigned elements=std::stoul(opt.at("--elements"));
    unsigned dim=1; while(dim*dim<elements)++dim;
    const unsigned iterations=std::stoul(opt.at("--iterations"));
    const uint32_t seed=std::stoul(opt.at("--seed"));
    if(dim*dim!=elements||dim>8||iterations==0||opt.at("--mode")!="hw"||
       opt.at("--control")!="legacy"||opt.at("--kernel")!="mmul_sysbase")
      throw std::runtime_error("Unsupported pilot configuration");
    const auto device_index=std::stoul(opt.at("--device"));
    if(device_index>std::numeric_limits<unsigned>::max())throw std::runtime_error("Device index out of range");
    xrt::device device(static_cast<unsigned>(device_index));
    const auto uuid=device.load_xclbin(opt.at("--xclbin"));
    xrt::kernel kernel(device,uuid,"mmul_sysbase",xrt::kernel::cu_access_mode::exclusive);
    const size_t bytes=elements*sizeof(uint32_t);
    xrt::bo bo_a(device,bytes,kernel.group_id(0)),bo_b(device,bytes,kernel.group_id(1)),bo_c(device,bytes,kernel.group_id(2));
    auto a=bo_a.map<uint32_t*>(),b=bo_b.map<uint32_t*>(),c=bo_c.map<uint32_t*>();
    std::ofstream csv(opt.at("--csv"));
    if(!csv)throw std::runtime_error("Cannot create benchmark CSV");
    csv<<"mode,kernel,elements,iteration,verify_ok,h2d_ms,kernel_ms,d2h_ms,total_ms,error_register\n";
    bool verified=true;
    for(unsigned iteration=0;iteration<iterations;++iteration) {
      if(opt.count("--matrix-a-path")) {
        const auto ma=matrix(opt.at("--matrix-a-path"),dim),mb=matrix(opt.at("--matrix-b-path"),dim);
        std::copy(ma.begin(),ma.end(),a);std::copy(mb.begin(),mb.end(),b);
      } else {
        std::mt19937 rng(seed+iteration);std::uniform_int_distribution<uint32_t> dist(0,255);
        for(unsigned i=0;i<elements;++i){a[i]=dist(rng);b[i]=dist(rng);}
      }
      std::vector<uint32_t> expected(elements,0);
      for(unsigned i=0;i<dim;++i)for(unsigned j=0;j<dim;++j)for(unsigned k=0;k<dim;++k)
        expected[i*dim+j]+=uint32_t(uint64_t(a[i*dim+k])*b[k*dim+j]);
      std::fill(c,c+elements,0xdeadbeef);
      const auto t0=Clock::now();
      bo_a.sync(XCL_BO_SYNC_BO_TO_DEVICE);bo_b.sync(XCL_BO_SYNC_BO_TO_DEVICE);bo_c.sync(XCL_BO_SYNC_BO_TO_DEVICE);
      const auto t1=Clock::now();
      auto run=kernel(bo_a,bo_b,bo_c,dim);
      const auto state=run.wait(std::chrono::milliseconds(10000));
      if(state!=ERT_CMD_STATE_COMPLETED) throw std::runtime_error("Kernel did not complete successfully");
      const auto t2=Clock::now();
      const auto error=kernel.read_register(0x38);
      bo_c.sync(XCL_BO_SYNC_BO_FROM_DEVICE);
      const auto t3=Clock::now();
      bool ok=error==0;
      for(unsigned i=0;i<elements;++i)if(c[i]!=expected[i]) {
        std::cerr<<"Mismatch iteration="<<iteration<<" index="<<i<<" expected="<<expected[i]<<" actual="<<c[i]<<"\n";
        ok=false;break;
      }
      csv<<"hw,mmul_sysbase,"<<elements<<','<<iteration<<','<<(ok?1:0)<<','
         <<ms(t0,t1)<<','<<ms(t1,t2)<<','<<ms(t2,t3)<<','<<ms(t0,t3)<<','<<error<<'\n';
      csv.flush();verified &= ok;
      if(!ok)break;
    }
    std::cout<<"SYSBASE_HARDWARE_VERIFY="<<(verified?"PASS":"FAIL")<<" UUID="<<uuid.to_string()<<"\n";
    return verified?0:2;
  } catch(const std::exception& error) {std::cerr<<"ERROR: "<<error.what()<<'\n';return 1;}
}
